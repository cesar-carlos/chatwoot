require 'rails_helper'

RSpec.describe V2::Reports::ServiceSessions::SummaryBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:since_time) { 1.week.ago.beginning_of_day }
  let(:until_time) { Time.current.end_of_day }
  let(:params) do
    {
      since: since_time.to_i,
      until: until_time.to_i,
      business_hours: false
    }
  end
  let(:builder) { described_class.new(account: account, params: params) }

  describe '#build' do
    context 'when there are open and closed sessions in range' do
      let!(:open_conversation) do
        create(
          :conversation,
          account: account,
          inbox: inbox,
          assignee: user,
          status: :open,
          created_at: 2.days.ago
        )
      end
      let!(:closed_conversation) do
        create(
          :conversation,
          account: account,
          inbox: inbox,
          assignee: user,
          status: :resolved,
          created_at: 3.days.ago
        )
      end

      before do
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: open_conversation,
          user: user,
          name: 'conversation_opened',
          value: 0,
          event_start_time: 2.days.ago,
          event_end_time: 2.days.ago
        )
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: closed_conversation,
          user: user,
          name: 'conversation_resolved',
          value: 120,
          value_in_business_hours: 90,
          event_start_time: 3.days.ago,
          event_end_time: 2.days.ago
        )
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: closed_conversation,
          user: user,
          name: 'first_response',
          value: 30,
          value_in_business_hours: 20,
          event_start_time: 3.days.ago,
          event_end_time: 2.days.ago
        )
      end

      it 'returns basic session metrics' do
        report = builder.build

        expect(report[:open_sessions_count]).to eq(1)
        expect(report[:closed_sessions_count]).to eq(1)
        expect(report[:total_sessions]).to eq(2)
        expect(report[:avg_session_duration]).to eq(120.0)
        expect(report[:avg_first_response_time]).to eq(30.0)
        expect(report[:reopen_rate]).to eq(0.0)
      end

      it 'returns percentile durations for the single sample' do
        report = builder.build

        expect(report[:p95_session_resolution_time]).to eq(120)
        expect(report[:p95_first_response_time]).to eq(30)
      end

      it 'uses business-hour durations when business_hours is true' do
        report = described_class.new(
          account: account,
          params: params.merge(business_hours: true)
        ).build

        expect(report[:open_sessions_count]).to eq(1)
        expect(report[:closed_sessions_count]).to eq(1)
        expect(report[:avg_session_duration]).to eq(90.0)
        expect(report[:avg_first_response_time]).to eq(20.0)
        expect(report[:p95_session_resolution_time]).to eq(90)
        expect(report[:p95_first_response_time]).to eq(20)
      end
    end

    context 'when open session cycle start is outside the date range' do
      let!(:stale_open_conversation) do
        create(
          :conversation,
          account: account,
          inbox: inbox,
          assignee: user,
          status: :open,
          created_at: 2.months.ago,
          last_activity_at: 1.day.ago
        )
      end

      before do
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: stale_open_conversation,
          user: user,
          name: 'conversation_opened',
          value: 0,
          event_start_time: 2.months.ago,
          event_end_time: 2.months.ago
        )
      end

      it 'excludes the session from open counts based on cycle start' do
        report = builder.build

        expect(report[:open_sessions_count]).to eq(0)
      end

      it 'still includes the session in backlog aging metrics' do
        report = builder.build

        expect(report[:open_sessions_aging_buckets][:over_24h]).to eq(1)
      end
    end

    context 'when inbox lock_to_single_conversation is disabled' do
      let(:legacy_inbox) do
        create(:inbox, account: account, lock_to_single_conversation: false)
      end
      let!(:reopened_conversation) do
        create(
          :conversation,
          account: account,
          inbox: legacy_inbox,
          assignee: user,
          status: :open,
          created_at: 2.months.ago
        )
      end

      before do
        create(
          :reporting_event,
          account: account,
          inbox: legacy_inbox,
          conversation: reopened_conversation,
          user: user,
          name: 'conversation_opened',
          value: 0,
          event_start_time: 2.months.ago,
          event_end_time: 2.months.ago
        )
        create(
          :reporting_event,
          account: account,
          inbox: legacy_inbox,
          conversation: reopened_conversation,
          user: user,
          name: 'conversation_opened',
          value: 3600,
          event_start_time: 1.week.ago,
          event_end_time: 1.week.ago
        )
      end

      it 'uses conversation created_at as cycle start for open session counts' do
        report = builder.build

        expect(report[:open_sessions_count]).to eq(0)
      end
    end

    context 'when inbox lock_to_single_conversation is enabled' do
      let(:locked_inbox) { create(:inbox, :single_history, account: account) }
      let!(:reopened_conversation) do
        create(
          :conversation,
          account: account,
          inbox: locked_inbox,
          assignee: user,
          status: :open,
          created_at: 2.months.ago
        )
      end

      before do
        create(
          :reporting_event,
          account: account,
          inbox: locked_inbox,
          conversation: reopened_conversation,
          user: user,
          name: 'conversation_opened',
          value: 0,
          event_start_time: 2.months.ago,
          event_end_time: 2.months.ago
        )
        create(
          :reporting_event,
          account: account,
          inbox: locked_inbox,
          conversation: reopened_conversation,
          user: user,
          name: 'conversation_opened',
          value: 3600,
          event_start_time: 2.days.ago,
          event_end_time: 2.days.ago
        )
      end

      it 'counts the open session from the latest conversation_opened event' do
        report = builder.build

        expect(report[:open_sessions_count]).to eq(1)
      end
    end

    context 'when evolution_pending_since is later than the last open event' do
      let(:locked_inbox) { create(:inbox, :single_history, account: account) }
      let!(:pending_cycle_conversation) do
        create(
          :conversation,
          account: account,
          inbox: locked_inbox,
          assignee: user,
          status: :open,
          created_at: 2.months.ago,
          additional_attributes: { evolution_pending_since: 1.day.ago.utc.iso8601(3) }
        )
      end

      before do
        create(
          :reporting_event,
          account: account,
          inbox: locked_inbox,
          conversation: pending_cycle_conversation,
          user: user,
          name: 'conversation_opened',
          value: 0,
          event_start_time: 2.months.ago,
          event_end_time: 2.months.ago
        )
      end

      it 'starts the open session at evolution_pending_since' do
        report = builder.build

        expect(report[:open_sessions_count]).to eq(1)
      end
    end

    context 'when conversations are reopened in the period' do
      let!(:closed_conversation) do
        create(
          :conversation,
          account: account,
          inbox: inbox,
          assignee: user,
          status: :resolved,
          created_at: 3.days.ago
        )
      end

      before do
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: closed_conversation,
          user: user,
          name: 'conversation_resolved',
          value: 100,
          event_start_time: 3.days.ago,
          event_end_time: 2.days.ago
        )
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: closed_conversation,
          user: user,
          name: 'conversation_opened',
          value: 0,
          event_start_time: 3.days.ago,
          event_end_time: 3.days.ago
        )
        2.times do
          create(
            :reporting_event,
            account: account,
            inbox: inbox,
            conversation: closed_conversation,
            user: user,
            name: 'conversation_opened',
            value: 3600,
            event_start_time: 1.day.ago,
            event_end_time: 1.day.ago
          )
        end
      end

      it 'divides reopen events by closed sessions and ignores first opens' do
        report = builder.build

        expect(report[:closed_sessions_count]).to eq(1)
        expect(report[:reopen_rate]).to eq(2.0)
      end
    end
  end
end
