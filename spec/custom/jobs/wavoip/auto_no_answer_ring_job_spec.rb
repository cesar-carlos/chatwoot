# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::AutoNoAnswerRingJob do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :wavoip,
      provider_call_id: 'auto_no_answer_001',
      direction: :incoming,
      status: 'ringing'
    )
  end
  let!(:message) do
    msg = Voice::CallMessageBuilder.new(call).perform!
    call.update!(message_id: msg.id)
    msg
  end

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
  end

  it 'force-closes a call still ringing as no_answer' do
    broadcaster = instance_double(Wavoip::Calls::Broadcaster, broadcast_ended: true)
    allow(Wavoip::Calls::Broadcaster).to receive(:new).with(inbox: inbox).and_return(broadcaster)

    described_class.perform_now(call.id)

    aggregate_failures do
      expect(call.reload.status).to eq('no_answer')
      expect(call.end_reason).to eq('no_answer')
      expect(call.meta['auto_timeout']).to be(true)
      expect(broadcaster).to have_received(:broadcast_ended).with(call)
    end
  end

  it 'updates the voice_call message status' do
    described_class.perform_now(call.id)

    expect(message.reload.content_attributes.dig('data', 'status')).to eq('no-answer')
  end

  it 'does nothing when the call already reached a terminal status' do
    call.update!(status: 'completed')
    broadcaster = instance_double(Wavoip::Calls::Broadcaster)
    allow(Wavoip::Calls::Broadcaster).to receive(:new).and_return(broadcaster)

    described_class.perform_now(call.id)

    expect(Wavoip::Calls::Broadcaster).not_to have_received(:new)
  end

  it 'also closes stuck outbound ringing calls' do
    call.update!(direction: :outgoing)

    described_class.perform_now(call.id)

    expect(call.reload.status).to eq('no_answer')
  end

  it 'no-ops for a missing call id' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
