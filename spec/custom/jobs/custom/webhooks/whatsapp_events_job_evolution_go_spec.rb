# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Webhooks::WhatsappEventsJobEvolutionGo do
  before do
    allow_any_instance_of(Inbox).to receive(:create_default_working_hours) # rubocop:disable RSpec/AnyInstance
  end

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
        'instance_token' => 'token'
      )
    )
  end
  let(:inbox) { channel.inbox }

  before do
    allow_any_instance_of(Inbox).to receive(:create_default_working_hours) # rubocop:disable RSpec/AnyInstance
    channel
  end

  it 'dispatches MESSAGE events through the normalizer' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_inbound.json').read)
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect(Custom::Whatsapp::Webhooks::EvolutionGoNormalizer).to receive(:new)
      .with(channel, hash_including('event' => 'MESSAGE'))
      .and_call_original

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.to change(Message, :count).by(1)
  end

  it 'dispatches READ_RECEIPT events as statuses' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/read_receipt.json').read)
    payload['event'] = 'READ_RECEIPT'
    conversation = create(:conversation, account: account, inbox: inbox)
    existing = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: '3EB0READRECEIPT01',
      status: :delivered
    )

    normalized = Custom::Whatsapp::Webhooks::EvolutionGoReadReceiptNormalizer.new(channel, payload).perform
    expect(normalized).to be_present

    Custom::Whatsapp::EvolutionGo::InboundMessageProcessor.process(
      channel,
      normalized.merge(phone_number: channel.phone_number)
    )

    expect(existing.reload.status).to eq('read')
  end

  it 'routes READ_RECEIPT events through the read receipt normalizer in the job' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/read_receipt.json').read)
    payload['event'] = 'READ_RECEIPT'
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect(Custom::Whatsapp::Webhooks::EvolutionGoReadReceiptNormalizer).to receive(:new)
      .with(channel, hash_including('event' => 'READ_RECEIPT'))
      .and_call_original

    Webhooks::WhatsappEventsJob.perform_now(job_payload)
  end

  it 'enqueues group metadata fetch for GROUP events when groups are enabled' do
    channel.update!(
      provider_config: channel.provider_config.merge('ignore_groups' => false)
    )
    payload = {
      'event' => 'GROUP',
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id,
      'data' => { 'groupJid' => '120363012345678901@g.us' }
    }

    expect(Custom::Whatsapp::Evolution::GroupMetadataFetchJob).to receive(:perform_later)
      .with(channel.id, '120363012345678901@g.us')

    Webhooks::WhatsappEventsJob.perform_now(payload)
  end

  it 'skips GROUP events when ignore_groups is enabled' do
    payload = {
      'event' => 'GROUP',
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id,
      'data' => { 'groupJid' => '120363012345678901@g.us' }
    }

    expect(Custom::Whatsapp::Evolution::GroupMetadataFetchJob).not_to receive(:perform_later)

    Webhooks::WhatsappEventsJob.perform_now(payload)
  end

  it 'syncs phone-sent SendMessage events into the existing conversation' do
    config = channel.provider_config.merge('ignore_from_me_echo' => false)
    channel.update_columns(provider_config: config) # rubocop:disable Rails/SkipsModelValidations
    channel.provider_config = config

    contact = create(:contact, account: account, phone_number: '+556696971841', name: 'Cesar Carlos')
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566996971841')
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_send_phone.json').read)
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.to change(Message, :count).by(1)
                                  .and not_change(Conversation, :count)
      .and not_change(ContactInbox, :count)

    message = Message.find_by!(source_id: payload.dig('data', 'Info', 'ID'))
    expect(message.conversation.contact_inbox).to eq(contact_inbox)
    expect(message.content).to eq('Mensagem enviada pelo celular')
  end

  it 'syncs phone-sent SendMessage events when ignore_from_me_echo is disabled' do
    config = channel.provider_config.merge('ignore_from_me_echo' => false)
    channel.update_columns(provider_config: config) # rubocop:disable Rails/SkipsModelValidations
    channel.provider_config = config
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_send_phone.json').read)
    payload['data']['Info']['ID'] = '3EB0PHONE-SENT-002'
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.to change(Message, :count).by(1)

    message = Message.find_by!(source_id: '3EB0PHONE-SENT-002')
    aggregate_failures do
      expect(message.outgoing?).to be(true)
      expect(message.content).to eq('Mensagem enviada pelo celular')
      expect(message.source_id).to eq('3EB0PHONE-SENT-002')
      expect(message.content_attributes['phone_sent']).to be(true)
    end
  end

  it 'ignores SendMessage events when ignore_from_me_echo is enabled' do
    config = channel.provider_config.merge('ignore_from_me_echo' => true)
    channel.update_columns(provider_config: config) # rubocop:disable Rails/SkipsModelValidations
    channel.provider_config = config
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_send_phone.json').read)
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.not_to change(Message, :count)
  end

  it 'syncs phone-sent SendMessage to group when ignore_from_me_echo and ignore_groups are disabled' do
    config = channel.provider_config.merge('ignore_from_me_echo' => false, 'ignore_groups' => false)
    channel.update_columns(provider_config: config) # rubocop:disable Rails/SkipsModelValidations
    channel.provider_config = config

    group_jid = '120363012345678901@g.us'
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
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.to change(Message, :count).by(1)

    message = Message.find_by!(source_id: '3EB0PHONEGRP00001')
    aggregate_failures do
      expect(message.outgoing?).to be(true)
      expect(message.content).to eq('Mensagem enviada pelo celular para o grupo')
      expect(message.content_attributes['phone_sent']).to be(true)
      expect(message.conversation.contact_inbox).to eq(contact_inbox)
    end
  end

  it 'syncs MESSAGE fromMe to group when ignore_from_me_echo and ignore_groups are disabled' do
    config = channel.provider_config.merge('ignore_from_me_echo' => false, 'ignore_groups' => false)
    channel.update_columns(provider_config: config) # rubocop:disable Rails/SkipsModelValidations
    channel.provider_config = config

    group_jid = '120363012345678901@g.us'
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
    payload['event'] = 'Message'
    payload['data']['Info']['ID'] = '3EB0PHONEGRPMSG01'
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.to change(Message, :count).by(1)

    message = Message.find_by!(source_id: '3EB0PHONEGRPMSG01')
    aggregate_failures do
      expect(message.outgoing?).to be(true)
      expect(message.content).to eq('Mensagem enviada pelo celular para o grupo')
      expect(message.content_attributes['phone_sent']).to be(true)
      expect(message.conversation.contact_inbox).to eq(contact_inbox)
    end
  end

  it 'skips SendMessage to group when ignore_groups is enabled' do
    config = channel.provider_config.merge('ignore_from_me_echo' => false, 'ignore_groups' => true)
    channel.update_columns(provider_config: config) # rubocop:disable Rails/SkipsModelValidations
    channel.provider_config = config

    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_send_phone_group.json').read)
    payload['data']['Info']['ID'] = '3EB0PHONEGRPIGNO1'
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.not_to change(Message, :count)
  end

  it 'skips MESSAGE fromMe to group when ignore_from_me_echo is enabled' do
    config = channel.provider_config.merge('ignore_from_me_echo' => true, 'ignore_groups' => false)
    channel.update_columns(provider_config: config) # rubocop:disable Rails/SkipsModelValidations
    channel.provider_config = config

    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_send_phone_group.json').read)
    payload['event'] = 'Message'
    payload['data']['Info']['ID'] = '3EB0PHONEGRPECHO1'
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.not_to change(Message, :count)
  end

  it 'soft deletes via MESSAGE protocol revoke' do
    conversation = create(:conversation, account: account, inbox: inbox)
    existing = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      source_id: '3EB0DELETEDMSG123',
      content: 'will be deleted'
    )
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_revoke.json').read)
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    Webhooks::WhatsappEventsJob.perform_now(job_payload)

    existing.reload
    expect(existing.content_attributes['deleted']).to be(true)
  end

  it 'consumes revoke without soft-delete when mark_inbound_deleted is disabled' do
    channel.update!(
      provider_config: channel.provider_config.merge('mark_inbound_deleted' => false)
    )
    conversation = create(:conversation, account: account, inbox: inbox)
    existing = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      source_id: '3EB0DELETEDMSG123',
      content: 'will stay'
    )
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_revoke.json').read)
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.not_to change(Message, :count)

    existing.reload
    expect(existing.content_attributes['deleted']).not_to be(true)
    expect(existing.content).to eq('will stay')
  end

  it 'updates content via MESSAGE protocol edit' do
    conversation = create(:conversation, account: account, inbox: inbox)
    existing = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      source_id: 'AC9A902ED6D1458D0A9FB5C4023580E7',
      content: 'original'
    )
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_edit.json').read)
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    Webhooks::WhatsappEventsJob.perform_now(job_payload)

    existing.reload
    expect(existing.content).to include('Texto atualizado pelo cliente')
    expect(existing.content_attributes['edited']).to be(true)
  end

  it 'does not create unsupported placeholder for secretEncryptedMessage edits' do
    conversation = create(:conversation, account: account, inbox: inbox)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      source_id: 'ACE6C86D3693CAD6E8EDEA53051A87BA',
      content: 'Teste edição'
    )
    payload = JSON.parse(
      Rails.root.join('spec/fixtures/evolution_go/message_edit_secret_encrypted.json').read
    )
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.not_to change(Message, :count)

    expect(inbox.messages.where(content: '[Unsupported message type]')).to be_empty
  end

  it 'skips leftover protocolMessage-only MESSAGE events without creating a bubble' do
    job_payload = {
      'event' => 'MESSAGE',
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id,
      'data' => {
        'Info' => {
          'ID' => 'PROTO-NOISE-JOB-1',
          'Chat' => '5511999999999@s.whatsapp.net',
          'IsFromMe' => false,
          'Timestamp' => 1_699_999_999
        },
        'Message' => {
          'protocolMessage' => {
            'type' => 3,
            'typeName' => 'EPHEMERAL_SETTING'
          }
        }
      }
    }

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.not_to change(Message, :count)

    expect(inbox.messages.where(content: '[Unsupported message type]')).to be_empty
  end

  it 'processes SEND_MESSAGE revoke even when ignore_from_me_echo is enabled' do
    config = channel.provider_config.merge('ignore_from_me_echo' => true)
    channel.update_columns(provider_config: config) # rubocop:disable Rails/SkipsModelValidations
    channel.provider_config = config

    conversation = create(:conversation, account: account, inbox: inbox)
    existing = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: '3EB0PHONE-DELETE-1',
      content: 'delete me'
    )
    payload = {
      'event' => 'SEND_MESSAGE',
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id,
      'data' => {
        'Info' => {
          'ID' => 'PROTOCOL-PHONE-REVOKE',
          'Chat' => '5511999999999@s.whatsapp.net',
          'IsFromMe' => true
        },
        'Message' => {
          'protocolMessage' => {
            'type' => 'REVOKE',
            'key' => {
              'id' => '3EB0PHONE-DELETE-1',
              'remoteJid' => '5511999999999@s.whatsapp.net',
              'fromMe' => true
            }
          }
        }
      }
    }

    Webhooks::WhatsappEventsJob.perform_now(payload)

    expect(existing.reload.content_attributes['deleted']).to be(true)
  end

  it 'applies reactionMessage onto the target message without creating a new message' do
    conversation = create(:conversation, account: account, inbox: inbox)
    existing = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: 'TARGETMSG-REACT',
      content: 'Hello'
    )

    payload = {
      'event' => 'MESSAGE',
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id,
      'data' => {
        'key' => {
          'remoteJid' => '5511999999999@s.whatsapp.net',
          'fromMe' => false,
          'id' => 'REACTION-JOB-1'
        },
        'message' => {
          'reactionMessage' => {
            'text' => '👍',
            'key' => {
              'id' => 'TARGETMSG-REACT',
              'remoteJid' => '5511999999999@s.whatsapp.net',
              'fromMe' => true
            }
          }
        }
      }
    }

    expect do
      Webhooks::WhatsappEventsJob.perform_now(payload)
    end.not_to change(Message, :count)

    reactions = existing.reload.content_attributes['reactions']
    expect(reactions.size).to eq(1)
    expect(reactions.first['emoji']).to eq('👍')
  end

  it 'delegates unknown evolution_go channels to super without dropping' do
    payload = {
      'event' => 'MESSAGE',
      'evolution_go_instance_name' => 'missing',
      'channel_id' => 0,
      'phone_number' => channel.phone_number,
      'contacts' => [{ 'wa_id' => '5511999999999', 'profile' => { 'name' => 'Test' } }],
      'messages' => [{
        'from' => '5511999999999',
        'id' => 'msg-1',
        'timestamp' => '1',
        'type' => 'text',
        'text' => { 'body' => 'hello' }
      }]
    }

    expect do
      Webhooks::WhatsappEventsJob.perform_now(payload)
    end.to change(Message, :count).by(1)
  end
end
