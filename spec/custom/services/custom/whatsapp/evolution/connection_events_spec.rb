# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::ConnectionEvents do
  subject(:handler) do
    described_class.new(channel: channel, connection_service: connection_service)
  end

  let(:account) { create(:account) }
  let(:connection_service) { Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      phone_number: '+55000f34332563f',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'instance_name' => 'test-instance',
        'api_key' => 'TEST-INSTANCE-API-KEY',
        'connection_status' => 'connecting'
      )
    )
  end
  let(:inbox) { channel.inbox }

  def load_fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/evolution/#{name}.json").read)
  end

  describe '#handle_event' do
    let(:broadcasts) { [] }

    before do
      allow(ActionCable.server).to receive(:broadcast) do |stream, payload|
        broadcasts << { stream: stream, payload: payload }
      end
    end

    it 'updates connection status and phone number on CONNECTION_UPDATE open' do
      envelope = load_fixture('connection_update_open')

      handler.handle_event(envelope)

      channel.reload
      expect(channel.provider_config['connection_status']).to eq('open')
      expect(channel.phone_number).to eq('+556681128433')
      open_broadcast = broadcasts.find { |entry| entry[:payload][:connection_status] == 'open' }
      expect(open_broadcast[:stream]).to eq("evolution:connection:#{inbox.id}")
      expect(open_broadcast[:payload][:phone_number]).to eq('+556681128433')
    end

    it 'broadcasts disconnect alert when connection closes' do
      channel.update!(
        provider_config: channel.provider_config.merge('connection_status' => 'open')
      )
      broadcaster = instance_double(Custom::Whatsapp::Evolution::Broadcaster, broadcast_disconnected: nil)
      allow(Custom::Whatsapp::Evolution::Broadcaster).to receive(:new).and_return(broadcaster)

      handler.handle_event(
        event: 'CONNECTION_UPDATE',
        data: { state: 'close' }
      )

      expect(broadcaster).to have_received(:broadcast_disconnected)
    end

    it 'stores and broadcasts QR data on QRCODE_UPDATED' do
      envelope = load_fixture('qrcode_updated')

      handler.handle_event(envelope)

      channel.reload
      expect(channel.provider_config['last_qr_base64']).to start_with('data:image/png;base64,')
      qr_broadcast = broadcasts.find { |entry| entry[:payload][:qrcode_base64].present? }
      expect(qr_broadcast[:payload][:qrcode_base64]).to start_with('data:image/png;base64,')
    end
  end

  describe '#qrcode_storage_attrs' do
    it 'extracts base64 without treating QR token as pairing code' do
      qrcode = load_fixture('qrcode_updated')['data']

      attrs = handler.qrcode_storage_attrs(qrcode)

      expect(attrs['last_qr_base64']).to start_with('data:image/png;base64,')
      expect(attrs['last_qr_code']).to be_nil
    end

    it 'stores eight-character pairing codes' do
      attrs = handler.qrcode_storage_attrs(
        'pairingCode' => 'ABCD1234',
        'base64' => 'data:image/png;base64,x'
      )

      expect(attrs['last_qr_code']).to eq('ABCD1234')
    end

    it 'returns empty hash for non-hash input' do
      expect(handler.qrcode_storage_attrs('invalid')).to eq({})
    end
  end
end
