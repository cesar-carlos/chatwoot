# frozen_string_literal: true

class Custom::ConversationWorkflow::SendMessageToContactService
  # rubocop:disable Metrics/ParameterLists -- workflow send needs trigger + destination context
  def initialize(account:, rule:, conversation:, inbox_id:, contact_id:, message_template:)
    @account = account
    @rule = rule
    @conversation = conversation
    @inbox_id = inbox_id
    @contact_id = contact_id
    @message_template = message_template
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- interpolate, resolve dest, send
  def perform
    # Interpolate against the *trigger* conversation (not the target) before MessageBuilder,
    # otherwise Liquidable would resolve vars from the destination contact.
    content = Custom::Liquid::MessageContentRenderer.render(
      @message_template,
      conversation: @conversation,
      executed_by: @rule
    )
    if content.blank?
      skip!(
        'blank_message',
        trigger_conversation_id: @conversation.id
      )
      return
    end

    inbox = @account.inboxes.find_by(id: @inbox_id)
    contact = @account.contacts.find_by(id: @contact_id)
    if inbox.blank? || contact.blank?
      skip!(
        'missing_inbox_or_contact',
        inbox_id: @inbox_id,
        contact_id: @contact_id,
        inbox_found: inbox.present?,
        contact_found: contact.present?
      )
      return
    end

    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    if contact_inbox.blank?
      skip!(
        'contact_inbox_blank',
        inbox_id: inbox.id,
        channel: inbox.channel_type,
        contact_id: contact.id,
        has_phone: contact.phone_number.present?,
        has_email: contact.email.present?
      )
      return
    end

    target_conversation = ConversationBuilder.new(
      params: {},
      contact_inbox: contact_inbox
    ).perform
    if target_conversation.blank?
      skip!(
        'conversation_blank',
        contact_inbox_id: contact_inbox.id
      )
      return
    end

    Messages::MessageBuilder.new(
      nil,
      target_conversation,
      {
        content: content,
        private: false,
        content_attributes: { conversation_workflow_rule_id: @rule.id }
      }
    ).perform
  rescue StandardError => e
    skip!(
      'exception',
      inbox_id: @inbox_id,
      contact_id: @contact_id,
      error_class: e.class.name,
      error_message: e.message
    )
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  private

  def skip!(reason, metadata = {})
    Rails.logger.warn(
      "[ConversationWorkflow] send_message_to_contact skipped #{reason} " \
      "(rule_id=#{@rule.id} #{metadata.map { |k, v| "#{k}=#{v}" }.join(' ')})"
    )
    ConversationWorkflowRuleSkip.record!(
      rule: @rule,
      action_name: 'send_message_to_contact',
      reason: reason,
      metadata: metadata.merge(trigger_conversation_id: @conversation.id)
    )
  end
end
