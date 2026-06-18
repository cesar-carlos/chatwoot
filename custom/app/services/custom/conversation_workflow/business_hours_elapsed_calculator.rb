class Custom::ConversationWorkflow::BusinessHoursElapsedCalculator
  def initialize(inbox:, started_at:, ended_at: Time.current, max_calendar_days: nil)
    @inbox = inbox
    @started_at = started_at
    @ended_at = ended_at
    @max_calendar_days = max_calendar_days
  end

  def elapsed_minutes
    return total_elapsed_minutes unless @inbox.working_hours_enabled?

    minutes = 0
    cursor = @started_at.in_time_zone(@inbox.timezone)
    finish = @ended_at.in_time_zone(@inbox.timezone)
    return 0 if cursor >= finish

    days_iterated = 0
    while cursor < finish && days_iterated < max_days_limit
      day_end = cursor.end_of_day
      segment_end = [day_end, finish].min
      minutes += working_minutes_for_day(cursor, segment_end)
      cursor = day_end + 1.second
      days_iterated += 1
    end
    minutes
  end

  private

  def total_elapsed_minutes
    ((@ended_at - @started_at) / 60).floor
  end

  def max_days_limit
    return @max_calendar_days if @max_calendar_days.present?

    [((@ended_at - @started_at) / 1.day).ceil, 1].max
  end

  def working_minutes_for_day(start_time, end_time)
    working_hour = @inbox.working_hours.find_by(day_of_week: start_time.wday)
    return 0 if working_hour.blank? || working_hour.closed_all_day?

    return ((end_time - start_time) / 60).floor if working_hour.open_all_day?

    open_time = start_time.change(hour: working_hour.open_hour, min: working_hour.open_minutes)
    close_time = start_time.change(hour: working_hour.close_hour, min: working_hour.close_minutes)
    overlap_start = [start_time, open_time].max
    overlap_end = [end_time, close_time].min
    return 0 if overlap_start >= overlap_end

    ((overlap_end - overlap_start) / 60).floor
  end
end
