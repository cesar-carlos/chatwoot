# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::MessageDeleteSyncService do
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
        'mark_inbound_deleted' => true
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

  it 'soft deletes matching incoming client messages when enabled' do
    message

    described_class.new(
      channel: channel,
      data: { key: { id: 'MSG-DELETE-1', fromMe: false } }
    ).perform

    message.reload
    expect(message.content).to eq('hello')
    expect(message.content_attributes['deleted']).to be(true)
    expect(message.content_attributes['deleted_via_evolution_go_webhook']).to be(true)
    expect(message.content_attributes['deleted_at']).to be_present
  end

  it 'soft deletes agent/phone messages when fromMe is true' do
    outgoing = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: 'MSG-DELETE-OUT',
      content: 'sent from phone'
    )

    described_class.new(
      channel: channel,
      data: { key: { id: 'MSG-DELETE-OUT', fromMe: true } }
    ).perform

    outgoing.reload
    expect(outgoing.content).to eq('sent from phone')
    expect(outgoing.content_attributes['deleted']).to be(true)
    expect(outgoing.content_attributes['deleted_via_evolution_go_webhook']).to be(true)
  end

  it 'does nothing when mark_inbound_deleted is disabled' do
    channel.update!(
      provider_config: channel.provider_config.merge('mark_inbound_deleted' => false)
    )
    message

    described_class.new(
      channel: channel,
      data: { key: { id: 'MSG-DELETE-1', fromMe: false } }
    ).perform

    expect(message.reload.content_attributes['deleted']).not_to be(true)
  end
end
