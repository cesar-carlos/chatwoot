# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::ConnectionService do
  subject(:service) { described_class.new(channel: channel) }

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
        'instance_token' => 'token',
        'instance_name' => 'test-go-instance',
        'connection_status' => 'open'
      )
    )
  end

  describe '#connection_payload' do
    it 'does not downgrade open to connecting when Go is still pairing' do
      stub_request(:get, 'https://go.example.com/instance/status')
        .to_return(
          status: 200,
          body: { message: 'success', data: { connected: true, loggedIn: false } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      payload = service.connection_payload

      expect(payload[:connection_status]).to eq('open')
      expect(channel.reload.provider_config['connection_status']).to eq('open')
    end
  end
end
