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

    it 'keeps a phone pairing code when the dashboard polls for a QR image' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'connection_status' => 'connecting',
          'last_qr_code' => 'ABCD1234'
        )
      )
      stub_request(:get, 'https://go.example.com/instance/status')
        .to_return(
          status: 200,
          body: { message: 'success', data: { connected: true, loggedIn: false } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      payload = service.connection_payload(include_qr: true)

      expect(payload[:qrcode_code]).to eq('ABCD1234')
      expect(WebMock).not_to have_requested(:get, 'https://go.example.com/instance/qr')
    end

    it 'omits a leftover QR image while a pairing code is active' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'connection_status' => 'connecting',
          'last_qr_code' => 'ABCD1234',
          'last_qr_base64' => 'old-image'
        )
      )
      stub_request(:get, 'https://go.example.com/instance/status')
        .to_return(
          status: 200,
          body: { message: 'success', data: { connected: true, loggedIn: false } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      payload = service.connection_payload(include_qr: true)

      expect(payload[:qrcode_base64]).to be_nil
      expect(payload[:qrcode_code]).to eq('ABCD1234')
    end
  end

  describe '#pair!' do
    it 'stores the pairing code and clears a previous QR image' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'connection_status' => 'close',
          'last_qr_base64' => 'old-image',
          'last_qr_code' => 'old-token'
        )
      )
      stub_request(:post, 'https://go.example.com/instance/pair')
        .to_return(
          status: 200,
          body: { message: 'success', data: { PairingCode: 'WXYZ9876' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = service.pair!(phone: '5511999999999')

      config = channel.reload.provider_config
      expect(result[:pairing_code]).to eq('WXYZ9876')
      expect(config['last_qr_code']).to eq('WXYZ9876')
      expect(config['last_qr_base64']).to be_nil
    end
  end

  describe '#update_connection_status' do
    before do
      stub_request(:get, 'https://go.example.com/instance/status')
        .to_return(
          status: 200,
          body: { message: 'success', data: { jid: '5511999999999@s.whatsapp.net', connected: true, loggedIn: true } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'enqueues import when a previous run is still marked running and the lock is free' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'connection_status' => 'connecting',
          'import_on_connect' => true,
          'import_messages' => true,
          'import_status' => 'running'
        )
      )
      allow(Redis::Alfred).to receive(:get).and_return(nil)
      allow(Custom::Whatsapp::EvolutionGo::ImportJob).to receive(:perform_later)

      service.update_connection_status('open')

      expect(Custom::Whatsapp::EvolutionGo::ImportJob).to have_received(:perform_later).with(channel.id)
    end

    it 'leaves a live import running when the lock is still held' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'connection_status' => 'connecting',
          'import_on_connect' => true,
          'import_messages' => true,
          'import_status' => 'running'
        )
      )
      allow(Redis::Alfred).to receive(:get).and_return('1')
      allow(Custom::Whatsapp::EvolutionGo::ImportJob).to receive(:perform_later)

      service.update_connection_status('open')

      expect(Custom::Whatsapp::EvolutionGo::ImportJob).not_to have_received(:perform_later)
    end
  end
end
