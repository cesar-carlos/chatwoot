# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Webhooks::Handlers::DeviceHandler do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:event) do
    Voice::Dto::WebhookCallEvent.new(
      provider: :wavoip,
      external_call_id: nil,
      action: :update,
      external_status: 'open',
      direction: nil,
      from_phone: channel.phone_number,
      to_phone: nil,
      peer_name: nil,
      duration_seconds: nil,
      session_id: 999,
      call_type: nil,
      record_url: nil,
      raw_type: 'DEVICE'
    )
  end

  it 'persists device status and session id' do
    described_class.new(inbox: inbox, event: event).perform

    channel.reload
    aggregate_failures do
      expect(channel.provider_config['device_status']).to eq('open')
      expect(channel.provider_config['id_session']).to eq(999)
      expect(channel.webhook_verified?).to be(true)
    end
  end
end
