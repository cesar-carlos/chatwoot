# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::PhoneOutgoingSyncService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_name' => 'test-go-instance',
        'instance_token' => 'token',
        'ignore_from_me_echo' => false,
        'ignore_groups' => false
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:group_jid) { '120363012345678901@g.us' }

  before { inbox }

  it 'does not create a message for protocol-only revoke payloads' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_revoke_pascal_case.json').read)

    expect do
      described_class.new(channel: channel, data: payload['data']).perform
    end.not_to change(Message, :count)
  end

  it 'releases the dedup lock when the payload is protocol-only' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_revoke_pascal_case.json').read)
    lock = instance_double(Whatsapp::MessageDedupLock, acquire!: true, release!: true)
    allow(Whatsapp::MessageDedupLock).to receive(:new).and_return(lock)

    described_class.new(channel: channel, data: payload['data']).perform

    expect(lock).to have_received(:release!)
  end

  it 'creates an outgoing message in the group conversation' do
    contact = create(
      :contact,
      account: account,
      phone_number: nil,
      identifier: group_jid,
      name: 'Support Team (GROUP)',
      additional_attributes: {
        Custom::Whatsapp::Evolution::GroupKeys::IS_WHATSAPP_GROUP_KEY => true,
        Custom::Whatsapp::Evolution::GroupKeys::EVOLUTION_GROUP_JID_KEY => group_jid
      }
    )
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: group_jid)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_send_phone_group.json').read)

    expect do
      described_class.new(channel: channel, data: payload['data']).perform
    end.to change(Message, :count).by(1)

    message = Message.find_by!(source_id: '3EB0PHONEGRP00001')
    aggregate_failures do
      expect(message.outgoing?).to be(true)
      expect(message.content).to eq('Mensagem enviada pelo celular para o grupo')
      expect(message.content_attributes['phone_sent']).to be(true)
      expect(message.content_attributes['external_echo']).to be(true)
      expect(message.conversation.contact_inbox).to eq(contact_inbox)
    end
  end

  it 'skips group messages when ignore_groups is enabled' do
    config = channel.provider_config.merge('ignore_groups' => true)
    channel.update_columns(provider_config: config) # rubocop:disable Rails/SkipsModelValidations
    channel.provider_config = config

    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_send_phone_group.json').read)
    lock = instance_double(Whatsapp::MessageDedupLock, acquire!: true, release!: true)
    allow(Whatsapp::MessageDedupLock).to receive(:new).and_return(lock)

    expect do
      described_class.new(channel: channel, data: payload['data']).perform
    end.not_to change(Message, :count)

    expect(Whatsapp::MessageDedupLock).not_to have_received(:new)
  end

  it 'stores the LID addressing jid (not the phone alt) on the echoed message' do
    contact = create(:contact, account: account, phone_number: '+556696971841')
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566996971841')
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_send_phone_lid_alt.json').read)

    described_class.new(channel: channel, data: payload['data']).perform

    message = Message.find_by!(source_id: '3EB0PHONELID00001')
    expect(message.content_attributes['evolution_go_remote_jid']).to eq('123456789012345@lid')
  end

  it 'scopes the outgoing echo dedup lock to the inbox' do
    contact = create(:contact, account: account, phone_number: '+556696971841')
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566996971841')
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_send_phone_lid_alt.json').read)
    allow(Whatsapp::MessageDedupLock).to receive(:new).and_call_original

    described_class.new(channel: channel, data: payload['data']).perform

    expect(Whatsapp::MessageDedupLock).to have_received(:new).with("inbox-#{inbox.id}-3EB0PHONELID00001")
  end

  it 'does not create a message when content is blank and there is no media' do
    contact = create(
      :contact,
      account: account,
      phone_number: nil,
      identifier: group_jid,
      name: 'Support Team (GROUP)',
      additional_attributes: {
        Custom::Whatsapp::Evolution::GroupKeys::IS_WHATSAPP_GROUP_KEY => true,
        Custom::Whatsapp::Evolution::GroupKeys::EVOLUTION_GROUP_JID_KEY => group_jid
      }
    )
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: group_jid)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

    # reactionMessage is skipped by the normalizer (no text bubble), so content stays blank
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_send_phone_group.json').read)
    payload['data']['Info']['ID'] = '3EB0PHONEGRPBLANK'
    payload['data']['Message'] = {
      'reactionMessage' => {
        'text' => '👍',
        'key' => { 'id' => 'TARGET', 'remoteJid' => group_jid, 'fromMe' => false }
      }
    }

    expect do
      described_class.new(channel: channel, data: payload['data']).perform
    end.not_to change(Message, :count)
  end
end
