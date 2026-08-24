# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::ConnectionEvents do
  subject(:handler) do
    described_class.new(channel: channel, connection_service: connection_service)
  end

  let(:account) { create(:account) }
  let(:connection_service) { Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: channel) }
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
        'connection_status' => 'connecting'
      )
    )
  end

  before do
    allow(ActionCable.server).to receive(:broadcast)
    stub_request(:get, 'https://go.example.com/instance/status')
      .to_return(
        status: 200,
        body: { message: 'success', data: { connected: true, loggedIn: true } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  describe '#handle_event' do
    it 'does not treat CONNECTED by event name as open without loggedIn' do
      handler.handle_event(event: 'CONNECTED', data: { connected: true, loggedIn: false })

      expect(channel.reload.provider_config['connection_status']).to eq('connecting')
    end

    it 'marks the session open when payload has connected and loggedIn' do
      handler.handle_event(event: 'CONNECTED', data: { connected: true, loggedIn: true })

      expect(channel.reload.provider_config['connection_status']).to eq('open')
    end

    it 'ignores residual QRCODE after the session is already open' do
      channel.update!(
        provider_config: channel.provider_config.merge('connection_status' => 'open')
      )

      handler.handle_event(
        event: 'QRCODE',
        data: { qrcode: 'data:image/png;base64,abc' }
      )

      channel.reload
      expect(channel.provider_config['connection_status']).to eq('open')
      expect(channel.provider_config['last_qr_base64']).to be_blank
      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    it 'does not downgrade an open session when pairing still reports connecting' do
      channel.update!(
        provider_config: channel.provider_config.merge('connection_status' => 'open')
      )

      handler.handle_event(event: 'CONNECTION', data: { connected: true, loggedIn: false })

      expect(channel.reload.provider_config['connection_status']).to eq('open')
      expect(ActionCable.server).not_to have_received(:broadcast)
    end
  end
end
