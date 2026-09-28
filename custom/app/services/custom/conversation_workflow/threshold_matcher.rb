class Custom::ConversationWorkflow::ThresholdMatcher
  def initialize(rule:, conversation:)
    @rule = rule
    @conversation = conversation
  end

  def matched?
    return simple_cutoff_matched? unless @rule.respect_business_hours?

    reference_time = reference_timestamp
    return false if reference_time.blank?

    elapsed = Custom::ConversationWorkflow::BusinessHoursElapsedCalculator.new(
      inbox: @conversation.inbox,
      started_at: reference_time,
      stop_after_minutes: @rule.duration_minutes
    ).elapsed_minutes
    elapsed >= @rule.duration_minutes
  end

  private

  def simple_cutoff_matched?
    reference_time = reference_timestamp
    return false if reference_time.blank?

    reference_time < @rule.duration_minutes.minutes.ago
  end

  def reference_timestamp
    Custom::ConversationWorkflow::ReferenceTimestamp.new(rule: @rule, conversation: @conversation).value
  end
end
