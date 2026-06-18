require 'rails_helper'

RSpec.describe Custom::ConversationWorkflow::BusinessHoursElapsedCalculator do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, working_hours_enabled: false) }

  it 'returns wall clock minutes when business hours disabled' do
    started_at = 2.hours.ago
    elapsed = described_class.new(inbox: inbox, started_at: started_at).elapsed_minutes

    expect(elapsed).to be >= 119
  end

  it 'limits calendar day iteration' do
    inbox.update!(working_hours_enabled: true)
    create(
      :working_hour,
      inbox: inbox,
      day_of_week: Time.zone.today.wday,
      open_all_day: true,
      closed_all_day: false
    )

    elapsed = described_class.new(
      inbox: inbox,
      started_at: 10.days.ago,
      ended_at: Time.current,
      max_calendar_days: 2
    ).elapsed_minutes

    expect(elapsed).to be < 10.days.in_minutes
  end
end
