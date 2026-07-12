# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::MessageDeleteSyncService do
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
      source_id: 'MSG-DELETE-1',
      content: 'hello'
    )
  end

  it 'soft deletes the matching message and flags webhook origin' do
    message

    described_class.new(
      channel: channel,
      data: { key: { id: 'MSG-DELETE-1' } }
    ).perform

    message.reload
    expect(message.content).to eq('hello')
    expect(message.content_attributes['deleted']).to be(true)
    expect(message.content_attributes['deleted_via_evolution_webhook']).to be(true)
    expect(message.content_attributes['deleted_at']).to be_present
  end
end
