# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Conversations::ResolutionCycle do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, lock_to_single_conversation: true) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, created_at: 3.days.ago)
  end

  describe '.start_time' do
    context 'when lock_to_single_conversation is disabled' do
      before { inbox.update!(lock_to_single_conversation: false) }

      it 'uses conversation created_at' do
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: conversation,
          name: 'conversation_opened',
          event_end_time: 1.hour.ago
        )

        expect(described_class.start_time(conversation)).to be_within(1.second).of(conversation.created_at)
      end
    end

    context 'when lock_to_single_conversation is enabled' do
      it 'uses the latest conversation_opened event' do
        opened_at = 2.hours.ago.change(usec: 0)
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: conversation,
          name: 'conversation_opened',
          event_end_time: opened_at
        )

        expect(described_class.start_time(conversation)).to be_within(1.second).of(opened_at)
      end

      it 'prefers evolution_pending_since when it is more recent than the last open event' do
        opened_at = 4.hours.ago.change(usec: 0)
        pending_since = 1.hour.ago.change(usec: 0)
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: conversation,
          name: 'conversation_opened',
          event_end_time: opened_at
        )
        conversation.update!(
          additional_attributes: { evolution_pending_since: pending_since.utc.iso8601(3) }
        )

        expect(described_class.start_time(conversation)).to be_within(1.second).of(pending_since)
      end

      it 'falls back to created_at when no cycle markers exist' do
        expect(described_class.start_time(conversation)).to be_within(1.second).of(conversation.created_at)
      end
    end
  end
end
