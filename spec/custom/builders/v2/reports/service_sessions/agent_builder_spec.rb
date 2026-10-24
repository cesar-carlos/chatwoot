require 'rails_helper'

RSpec.describe V2::Reports::ServiceSessions::AgentBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent_a) { create(:user, account: account, role: :agent) }
  let(:agent_b) { create(:user, account: account, role: :agent) }
  let(:params) do
    {
      since: 1.week.ago.beginning_of_day.to_i,
      until: Time.current.end_of_day.to_i
    }
  end
  let(:builder) { described_class.new(account: account, params: params) }

  before do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      assignee: agent_a,
      status: :open,
      created_at: 1.day.ago
    )
    resolved = create(
      :conversation,
      account: account,
      inbox: inbox,
      assignee: agent_a,
      status: :resolved,
      created_at: 2.days.ago
    )
    create(
      :reporting_event,
      account: account,
      inbox: inbox,
      conversation: resolved,
      user: agent_b,
      name: 'conversation_resolved',
      value: 80,
      event_start_time: 2.days.ago,
      event_end_time: 1.day.ago
    )
  end

  describe '#build' do
    it 'counts open sessions by current assignee and closed sessions by the event user' do
      rows = builder.build.index_by { |row| row[:id] }

      expect(rows[agent_a.id]).to include(open_sessions_count: 1, closed_sessions_count: 0)
      expect(rows[agent_b.id]).to include(open_sessions_count: 0, closed_sessions_count: 1, avg_session_duration: 80.0)
    end
  end
end
