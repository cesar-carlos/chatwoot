require 'rails_helper'

RSpec.describe Custom::ConversationWorkflow::BusinessHoursElapsedCalculator do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, working_hours_enabled: false) }

  it 'returns wall clock minutes when business hours disabled' do
    started_at = 2.hours.ago
    elapsed = described_class.new(inbox: inbox, started_at: started_at).elapsed_minutes

    expect(elapsed).to be >= 119
  end

  it 'counts business minutes across a closed weekend' do
    inbox.update!(working_hours_enabled: true, timezone: 'UTC')
    inbox.working_hours.delete_all
    create(
      :working_hour,
      inbox: inbox,
      day_of_week: 5,
      open_hour: 9,
      close_hour: 17
    )
    create(
      :working_hour,
      inbox: inbox,
      day_of_week: 1,
      open_hour: 9,
      close_hour: 17
    )
    inbox.reload

    elapsed = described_class.new(
      inbox: inbox,
      started_at: Time.zone.parse('2024-01-19 16:55:00'),
      ended_at: Time.zone.parse('2024-01-22 09:05:00'),
      stop_after_minutes: 10
    ).elapsed_minutes

    expect(elapsed).to eq(10)
  end

  it 'returns zero without iterating indefinitely when every day is closed' do
    inbox.update!(working_hours_enabled: true)
    inbox.working_hours.update_all(closed_all_day: true) # rubocop:disable Rails/SkipsModelValidations

    elapsed = described_class.new(
      inbox: inbox,
      started_at: 10.years.ago,
      ended_at: Time.current,
      stop_after_minutes: 10
    ).elapsed_minutes

    expect(elapsed).to eq(0)
  end
end
