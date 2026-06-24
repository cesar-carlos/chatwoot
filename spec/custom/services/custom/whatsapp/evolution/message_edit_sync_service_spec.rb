# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::MessageEditSyncService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'instance_name' => 'test-instance',
        'api_key' => 'TEST-KEY'
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
      content: 'original'
    )
  end

  it 'updates the original message and marks it as edited' do
    message

    described_class.new(
      channel: channel,
      data: {
        key: { id: 'MSG-EDIT-1', remoteJid: '5511999999999@s.whatsapp.net' },
        editedMessage: { conversation: 'updated body' }
      }
    ).perform

    message.reload
    expect(message.content).to include('updated body')
    expect(message.content_attributes['edited']).to be(true)
    expect(message.content_attributes['edited_at']).to be_present
  end

  it 'uses a stable -edited suffix when creating a fallback edited message' do
    service = described_class.new(channel: channel, data: {})
    payload = service.send(
      :build_upsert_payload,
      { id: 'MSG-EDIT-2', remoteJid: '5511999999999@s.whatsapp.net', fromMe: false },
      'edited body',
      nil
    )

    expect(payload.dig(:key, :id)).to eq('MSG-EDIT-2-edited')
  end
end
