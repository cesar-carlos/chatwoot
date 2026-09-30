class Custom::ConversationWorkflow::BusinessHoursElapsedCalculator
  def initialize(inbox:, started_at:, ended_at: Time.current, stop_after_minutes: nil)
    @inbox = inbox
    @started_at = started_at
    @ended_at = ended_at
    @stop_after_minutes = stop_after_minutes
  end

  def elapsed_minutes
    return total_elapsed_minutes unless @inbox.working_hours_enabled?

    minutes = 0
    cursor = @started_at.in_time_zone(@inbox.timezone)
    finish = @ended_at.in_time_zone(@inbox.timezone)
    return 0 if cursor >= finish
    return 0 unless open_days?

    while cursor < finish
      next_day = cursor.tomorrow.beginning_of_day
      segment_end = [next_day, finish].min
      minutes += working_minutes_for_day(cursor, segment_end)
      return minutes if stop_after_reached?(minutes)

      cursor = next_day
    end
    minutes
  end

  private

  def total_elapsed_minutes
    ((@ended_at - @started_at) / 60).floor
  end

  def open_days?
    working_hours_by_day.values.any? { |working_hour| !working_hour.closed_all_day? }
  end

  def stop_after_reached?(minutes)
    @stop_after_minutes.present? && minutes >= @stop_after_minutes
  end

  def working_hours_by_day
    @working_hours_by_day ||= @inbox.working_hours.index_by(&:day_of_week)
  end

  def working_minutes_for_day(start_time, end_time)
    working_hour = working_hours_by_day[start_time.wday]
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
