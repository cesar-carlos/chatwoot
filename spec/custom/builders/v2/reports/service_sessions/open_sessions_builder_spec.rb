require 'rails_helper'

RSpec.describe V2::Reports::ServiceSessions::OpenSessionsBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :single_history, account: account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:since_time) { 1.month.ago.beginning_of_day }
  let(:until_time) { Time.current.end_of_day }
  let(:params) do
    {
      since: since_time.to_i,
      until: until_time.to_i,
      page: 1,
      per_page: 1
    }
  end
  let(:builder) { described_class.new(account: account, params: params) }
  let!(:recent_activity_conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      assignee: user,
      status: :open,
      created_at: 10.days.ago,
      last_activity_at: 1.hour.ago
    )
  end
  let!(:recent_cycle_conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      assignee: user,
      status: :pending,
      created_at: 10.days.ago,
      last_activity_at: 5.days.ago
    )
  end

  before do
    create(
      :reporting_event,
      account: account,
      inbox: inbox,
      conversation: recent_activity_conversation,
      user: user,
      name: 'conversation_opened',
      value: 0,
      event_start_time: 10.days.ago,
      event_end_time: 10.days.ago
    )
    create(
      :reporting_event,
      account: account,
      inbox: inbox,
      conversation: recent_cycle_conversation,
      user: user,
      name: 'conversation_opened',
      value: 3600,
      event_start_time: 1.day.ago,
      event_end_time: 1.day.ago
    )
  end

  describe '#build' do
    it 'orders by cycle start and returns pagination metadata' do
      report = builder.build

      expect(report[:sessions].map { |session| session[:id] }).to eq([recent_cycle_conversation.id])
      expect(report[:sessions].first[:status]).to eq('pending')
      expect(report[:page]).to eq(1)
      expect(report[:per_page]).to eq(1)
      expect(report[:total_count]).to eq(2)
      expect(report[:total_pages]).to eq(2)
    end

    it 'caps per_page at 100' do
      report = described_class.new(
        account: account,
        params: params.merge(per_page: 500)
      ).build

      expect(report[:per_page]).to eq(100)
      expect(report[:sessions].size).to eq(2)
    end
  end
end
