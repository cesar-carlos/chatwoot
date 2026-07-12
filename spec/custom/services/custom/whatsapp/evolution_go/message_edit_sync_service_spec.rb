# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::MessageEditSyncService do
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
        'instance_token' => 'TEST-TOKEN',
        'mark_inbound_edited' => true
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      source_id: 'MSG-EDIT-1',
      content: 'original text'
    )
  end

  it 'updates the original message when client edits on WhatsApp' do
    message

    described_class.new(
      channel: channel,
      data: {
        key: { id: 'MSG-EDIT-1', fromMe: false },
        edited_body: 'updated text'
      }
    ).perform

    message.reload
    expect(message.content).to include('updated text')
    expect(message.content_attributes['edited']).to be(true)
    expect(message.content_attributes['edited_via_evolution_go_webhook']).to be(true)
  end

  it 'updates outgoing messages when agent edits from the phone' do
    outgoing = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: 'MSG-EDIT-OUT',
      content: 'sent from phone'
    )

    described_class.new(
      channel: channel,
      data: {
        key: { id: 'MSG-EDIT-OUT', fromMe: true },
        edited_body: 'edited on phone'
      }
    ).perform

    outgoing.reload
    expect(outgoing.content).to include('edited on phone')
    expect(outgoing.content_attributes['edited']).to be(true)
  end

  it 'skips noop when body already matches (loop prevention)' do
    message.update!(content: "#{described_class::EDITED_PREFIX}same body")

    expect do
      described_class.new(
        channel: channel,
        data: {
          key: { id: 'MSG-EDIT-1', fromMe: false },
          edited_body: 'same body'
        }
      ).perform
    end.not_to(change { message.reload.updated_at })
  end

  it 'does nothing when mark_inbound_edited is disabled' do
    channel.update!(
      provider_config: channel.provider_config.merge('mark_inbound_edited' => false)
    )
    message

    described_class.new(
      channel: channel,
      data: {
        key: { id: 'MSG-EDIT-1', fromMe: false },
        edited_body: 'updated text'
      }
    ).perform

    expect(message.reload.content).to eq('original text')
  end

  it 'skips fromMe edits when the original message is missing' do
    expect do
      described_class.new(
        channel: channel,
        data: {
          key: { id: 'MISSING-OUT', fromMe: true, remoteJid: '5511999999999@s.whatsapp.net' },
          edited_body: 'orphan edit'
        }
      ).perform
    end.not_to change(Message, :count)
  end
end
