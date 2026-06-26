# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::EscalateRingJob do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: create(:conversation, account: account, inbox: inbox),
      contact: create(:contact, account: account),
      provider: :wavoip,
      provider_call_id: 'escalate_test_001',
      direction: :incoming,
      status: 'ringing'
    )
  end

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
  end

  it 'broadcasts escalated ring when call is still ringing' do
    broadcaster = instance_double(Wavoip::Calls::Broadcaster, broadcast_escalated_ring: true)
    allow(Wavoip::Calls::Broadcaster).to receive(:new).with(inbox: inbox).and_return(broadcaster)

    described_class.perform_now(call.id)

    expect(broadcaster).to have_received(:broadcast_escalated_ring).with(call)
  end

  it 'does nothing when call is no longer ringing' do
    call.update!(status: 'completed')
    broadcaster = instance_double(Wavoip::Calls::Broadcaster)
    allow(Wavoip::Calls::Broadcaster).to receive(:new).and_return(broadcaster)

    described_class.perform_now(call.id)

    expect(Wavoip::Calls::Broadcaster).not_to have_received(:new)
  end

  it 'does not broadcast when offline fallback is none' do
    channel.update!(
      provider_config: channel.provider_config.merge('incoming_call_offline_fallback' => 'none')
    )
    payloads = []
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| payloads << [stream, payload] }

    described_class.perform_now(call.id)

    expect(payloads).to be_empty
  end
end
