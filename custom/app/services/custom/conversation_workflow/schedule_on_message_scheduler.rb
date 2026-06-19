class Custom::ConversationWorkflow::ScheduleOnMessageScheduler
  REDIS_KEY_PREFIX = 'conversation_workflow:schedule'.freeze
  MIN_WAIT_SECONDS = 1

  def initialize(rule:, conversation:)
    @rule = rule
    @conversation = conversation
  end

  def perform
    return unless ConversationWorkflowRule.schedulable_on_incoming?(@rule.trigger_type)
    return if @conversation.waiting_since.blank?
    return if @rule.first_response_overdue? && @conversation.first_reply_created_at.present?

    wait_seconds = wait_seconds_until_threshold(reference_time: @conversation.waiting_since)
    return if wait_seconds.nil?

    return unless claim_schedule_slot!(wait_seconds)

    Custom::ConversationWorkflow::ScheduleOnMessageJob
      .set(wait: wait_seconds.seconds)
      .perform_later(conversation_id: @conversation.id, rule_id: @rule.id)
  end

  def perform_for_outgoing_message(message)
    return unless @rule.customer_no_reply?
    return unless message.outgoing?

    wait_seconds = wait_seconds_until_threshold(reference_time: message.created_at)
    return if wait_seconds.nil?

    return unless claim_schedule_slot!(wait_seconds)

    Custom::ConversationWorkflow::ScheduleOnMessageJob
      .set(wait: wait_seconds.seconds)
      .perform_later(conversation_id: @conversation.id, rule_id: @rule.id)
  end

  private

  def wait_seconds_until_threshold(reference_time:)
    return if reference_time.blank?

    elapsed_minutes = ((Time.current - reference_time) / 60.0).floor
    remaining_minutes = @rule.duration_minutes - elapsed_minutes
    return MIN_WAIT_SECONDS if remaining_minutes <= 0

    remaining_minutes * 60
  end

  def claim_schedule_slot!(wait_seconds)
    Redis::Alfred.set(
      redis_key,
      Time.current.to_i,
      nx: true,
      ex: wait_seconds + 60
    )
  end

  def redis_key
    "#{REDIS_KEY_PREFIX}:#{@rule.id}:#{@conversation.id}"
  end
end
