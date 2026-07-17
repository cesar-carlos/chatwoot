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
      record_status: nil,
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

  it 'aliases connected to open before persist' do
    connected_event = event.with(external_status: 'connected')

    described_class.new(inbox: inbox, event: connected_event).perform

    expect(channel.reload.provider_config['device_status']).to eq('open')
  end

  it 'aliases disconnected to close before persist' do
    disconnected_event = event.with(external_status: 'disconnected')

    described_class.new(inbox: inbox, event: disconnected_event).perform

    expect(channel.reload.provider_config['device_status']).to eq('close')
  end

  it 'leaves other statuses unchanged' do
    hibernating_event = event.with(external_status: 'hibernating')

    described_class.new(inbox: inbox, event: hibernating_event).perform

    expect(channel.reload.provider_config['device_status']).to eq('hibernating')
  end
end
