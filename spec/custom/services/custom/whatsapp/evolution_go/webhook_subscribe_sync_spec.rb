# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::WebhookSubscribeSync do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'base_url' => 'https://go.example.com',
        'global_api_key' => 'global-key',
        'instance_token' => 'instance-token',
        'instance_name' => 'test-instance',
        'instance_id' => 'inst-1',
        'webhook_token' => 'secret',
        'ignore_groups' => true
      )
    )
  end
  let(:connection_service) { Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: channel) }
  let(:sync) { described_class.new(channel: channel, connection_service: connection_service) }

  around do |example|
    ClimateControl.modify(FRONTEND_URL: 'https://chatwoot.example.com') { example.run }
  end

  describe '.canonical_events' do
    it 'returns base events without GROUP when ignore_groups is true' do
      expect(described_class.canonical_events('ignore_groups' => true)).to eq(
        Custom::Whatsapp::EvolutionGo::ProviderConfig::WEBHOOK_EVENTS
      )
    end

    it 'includes GROUP when ignore_groups is false' do
      events = described_class.canonical_events('ignore_groups' => false)

      expect(events).to include('GROUP')
      expect(events).to include('MESSAGE', 'HISTORY_SYNC')
    end
  end

  describe '#merge_stored!' do
    it 'merges stored events with canonical list' do
      channel.update!(
        provider_config: channel.provider_config.merge('webhook_subscribe' => %w[MESSAGE CUSTOM_EVENT])
      )

      merged = sync.merge_stored!

      expect(merged).to include('MESSAGE', 'HISTORY_SYNC', 'CUSTOM_EVENT')
    end
  end

  describe '#sync!' do
    it 'connects with merged subscribe list and persists webhook_subscribe' do
      stub_request(:post, 'https://go.example.com/instance/connect')
        .with(
          body: hash_including(
            webhookUrl: %r{/webhooks/evolution_go/test-instance},
            subscribe: array_including('MESSAGE', 'READ_RECEIPT', 'HISTORY_SYNC')
          )
        )
        .to_return(status: 200, body: { message: 'success', data: {} }.to_json)

      events = sync.sync!

      expect(events).to include('MESSAGE', 'HISTORY_SYNC')
      expect(channel.reload.provider_config['webhook_subscribe']).to eq(events)
    end

    it 'preserves open connection_status when syncing webhooks' do
      channel.update!(
        provider_config: channel.provider_config.merge('connection_status' => 'open')
      )

      stub_request(:post, 'https://go.example.com/instance/connect')
        .to_return(status: 200, body: { message: 'success', data: {} }.to_json)

      sync.sync!

      expect(channel.reload.provider_config['connection_status']).to eq('open')
    end
  end
end
