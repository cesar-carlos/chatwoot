# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::HandledRemotelyStubService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:broadcaster) do
    instance_double(Wavoip::Calls::Broadcaster, broadcast_ended: nil)
  end
  let(:provider_call_id) { 'handled_remotely_stub_001' }

  def build_event(overrides = {})
    defaults = {
      provider: :wavoip,
      external_call_id: provider_call_id,
      action: :update,
      external_status: 'HANDLED_REMOTELY',
      direction: :incoming,
      from_phone: '+15550001111',
      to_phone: channel.phone_number,
      peer_name: 'Remote Caller',
      duration_seconds: nil,
      session_id: 12_345,
      call_type: :official,
      record_url: nil,
      record_status: nil,
      raw_type: 'CALL'
    }
    Voice::Dto::WebhookCallEvent.new(**defaults, **overrides)
  end

  def service_for(event)
    described_class.new(
      inbox: inbox,
      event: event,
      broadcaster: broadcaster,
      invalid_contact_phone: -> { false }
    )
  end

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
  end

  it 'creates an inbound stub call and broadcasts ended' do
    call = service_for(build_event).perform

    aggregate_failures do
      expect(call).to be_present
      expect(call.incoming?).to be(true)
      expect(call.status).to eq('completed')
      expect(call.end_reason).to eq('handled_remotely')
      expect(broadcaster).to have_received(:broadcast_ended).with(call)
      expect(channel.reload.webhook_verified?).to be(true)
    end
  end

  it 'uses ConversationLinker.link! so outbound direction is respected' do
    outbound_event = build_event(direction: :outgoing, from_phone: '+15550002222')
    allow(Wavoip::Calls::ConversationLinker).to receive(:link!).and_call_original

    call = service_for(outbound_event).perform

    expect(Wavoip::Calls::ConversationLinker).to have_received(:link!).with(
      inbox: inbox,
      event: outbound_event
    )
    expect(call.outgoing?).to be(true)
  end

  it 'returns nil when contact phone validation fails' do
    invalid = described_class.new(
      inbox: inbox,
      event: build_event,
      broadcaster: broadcaster,
      invalid_contact_phone: -> { true }
    )

    expect(invalid.perform).to be_nil
    expect(Call.find_by(provider_call_id: provider_call_id)).to be_nil
  end
end
