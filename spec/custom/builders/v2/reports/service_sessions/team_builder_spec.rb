require 'rails_helper'

RSpec.describe V2::Reports::ServiceSessions::TeamBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:params) do
    {
      since: 1.week.ago.beginning_of_day.to_i,
      until: Time.current.end_of_day.to_i
    }
  end
  let(:builder) { described_class.new(account: account, params: params) }

  describe '#build' do
    it 'lists every team and adds an unassigned row only when a session has no team' do
      create(
        :conversation,
        account: account,
        inbox: inbox,
        team: team,
        status: :open,
        created_at: 2.days.ago
      )
      create(
        :conversation,
        account: account,
        inbox: inbox,
        team: nil,
        status: :open,
        created_at: 1.day.ago
      )

      rows = builder.build.index_by { |row| row[:id] }

      expect(rows[team.id]).to include(open_sessions_count: 1, closed_sessions_count: 0)
      expect(rows[0]).to include(id: 0, name: nil, open_sessions_count: 1)
    end

    it 'omits the unassigned row when every open session has a team' do
      create(
        :conversation,
        account: account,
        inbox: inbox,
        team: team,
        status: :open,
        created_at: 1.day.ago
      )

      ids = builder.build.map { |row| row[:id] }

      expect(ids).to include(team.id)
      expect(ids).not_to include(0)
    end
  end
end
