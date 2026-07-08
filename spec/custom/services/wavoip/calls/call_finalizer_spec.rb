# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::CallFinalizer do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
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
      direction: :incoming,
      status: 'in_progress',
      accepted_by_agent_id: agent.id,
      provider_call_id: 'finalizer_001'
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

  describe '.sync_message_and_conversation!' do
    it 'updates the voice_call message status and conversation attributes' do
      call.update!(status: 'completed', duration_seconds: 42)

      described_class.sync_message_and_conversation!(call)

      aggregate_failures do
        expect(message.reload.content_attributes.dig('data', 'status')).to eq('completed')
        expect(message.content_attributes.dig('data', 'duration_seconds')).to eq(42)
        expect(conversation.reload.additional_attributes['call_status']).to eq('completed')
      end
    end

    it 'defaults the agent to call.accepted_by_agent' do
      call.update!(status: 'completed')

      described_class.sync_message_and_conversation!(call)

      expect(message.reload.content_attributes.dig('data', 'accepted_by')).to eq(
        { 'id' => agent.id, 'name' => agent.name }
      )
    end

    it 'accepts an explicit agent override (nil for system-driven finalizations)' do
      call.update!(status: 'completed')

      described_class.sync_message_and_conversation!(call, agent: nil)

      expect(message.reload.content_attributes.dig('data', 'accepted_by')).to be_nil
    end
  end

  describe '.finalize_ended!' do
    it 'syncs the message/conversation and broadcasts ended' do
      broadcaster = instance_double(Wavoip::Calls::Broadcaster, broadcast_ended: true)
      call.update!(status: 'completed', duration_seconds: 10)

      described_class.finalize_ended!(call, broadcaster: broadcaster)

      aggregate_failures do
        expect(message.reload.content_attributes.dig('data', 'status')).to eq('completed')
        expect(broadcaster).to have_received(:broadcast_ended).with(call)
      end
    end
  end
end
