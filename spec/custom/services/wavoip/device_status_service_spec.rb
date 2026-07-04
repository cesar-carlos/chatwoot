# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::DeviceStatusService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account, device_token: 'test-token') }
  let(:service) { described_class.new(channel: channel) }

  describe '#connection_payload' do
    it 'returns device status from channel config when live check is cached' do
      Rails.cache.write("wavoip:device_status:#{channel.id}", true, expires_in: 15.seconds)
      channel.update!(provider_config: channel.provider_config.merge('device_status' => 'open'))

      payload = service.connection_payload

      expect(payload[:device_status]).to eq('open')
      expect(payload[:phone_number]).to eq(channel.phone_number)
      expect(payload[:live]).to be(false)
    end

    it 'refreshes device status when forced' do
      stub_request(:get, "https://devices.wavoip.com/test-token/whatsapp/all_info")
        .to_return(
          status: 200,
          body: { result: { status: 'open', contact: { phone: '55669999050312' } } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      payload = service.connection_payload(force: true)

      expect(payload[:device_status]).to eq('open')
      expect(payload[:live]).to be(true)
      expect(payload[:contact_phone]).to eq('55669999050312')
    end
  end
end
