class Custom::ConversationWorkflow::ActionService < AutomationRules::ActionService
  def perform
    @rule.actions.each do |action|
      @conversation.reload
      action = action.with_indifferent_access
      begin
        dispatch_action(action)
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
        raise
      end
    end
  end

  private

  def dispatch_action(action)
    case action[:action_name]
    when 'send_message'
      send_message([action[:action_params]&.first, action[:counts_as_agent_reply]])
    when 'resolve_conversation'
      Custom::Conversations::ResolveService.new(conversation: @conversation, skip_required_attributes: true).perform
    when 'send_message_to_contact'
      send_message_to_contact(action[:action_params])
    else
      send(action[:action_name], action[:action_params])
    end
  end

  def send_message_to_contact(params)
    inbox_id, contact_id, message_template = Array(params)
    Custom::ConversationWorkflow::SendMessageToContactService.new(
      account: @account,
      rule: @rule,
      conversation: @conversation,
      inbox_id: inbox_id.to_i,
      contact_id: contact_id.to_i,
      message_template: message_template.to_s
    ).perform
  end

  def send_message(message)
    return if conversation_a_tweet?

    content, counts_as_reply = parse_send_message_args(message)
    params = {
      content: content,
      private: false,
      content_attributes: {
        conversation_workflow_rule_id: @rule.id,
        counts_as_agent_reply: counts_as_reply == true
      }
    }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
    clear_waiting_since_if_counts_as_reply!(counts_as_reply)
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = {
      content: message[0],
      private: true,
      content_attributes: { conversation_workflow_rule_id: @rule.id }
    }
    Messages::MessageBuilder.new(nil, @conversation.reload, params).perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(
      event: "workflow_rule.#{@rule.trigger_type}",
      conversation_workflow_rule_id: @rule.id
    )
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  def send_attachment(_blob_ids)
    Rails.logger.warn("send_attachment is not supported for conversation workflow rules (rule_id=#{@rule.id})")
  end

  def parse_send_message_args(message)
    if message.is_a?(Array) && message.length > 1 && [true, false].include?(message.last)
      [message[0], message.last]
    else
      [message.is_a?(Array) ? message[0] : message, false]
    end
  end

  def clear_waiting_since_if_counts_as_reply!(counts_as_reply)
    return unless counts_as_reply == true

    @conversation.update_column(:waiting_since, nil) # rubocop:disable Rails/SkipsModelValidations
  end
end
