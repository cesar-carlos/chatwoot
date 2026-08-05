class Custom::ConversationWorkflow::SendMessageToContactService
  TEMPLATE_VARIABLES = {
    'conversation.id' => ->(ctx) { ctx[:conversation].id },
    'conversation.display_id' => ->(ctx) { ctx[:conversation].display_id },
    'contact.name' => ->(ctx) { ctx[:conversation].contact&.name },
    'contact.email' => ->(ctx) { ctx[:conversation].contact&.email },
    'contact.phone' => ->(ctx) { ctx[:conversation].contact&.phone_number },
    'inbox.name' => ->(ctx) { ctx[:conversation].inbox&.name },
    'rule.name' => ->(ctx) { ctx[:rule].name }
  }.freeze

  def initialize(account:, rule:, conversation:, inbox_id:, contact_id:, message_template:)
    @account = account
    @rule = rule
    @conversation = conversation
    @inbox_id = inbox_id
    @contact_id = contact_id
    @message_template = message_template
  end

  def perform
    content = interpolate(@message_template)
    if content.blank?
      Rails.logger.warn(
        "[ConversationWorkflow] send_message_to_contact skipped blank message " \
        "(rule_id=#{@rule.id} trigger_conversation_id=#{@conversation.id})"
      )
      return
    end

    inbox = @account.inboxes.find_by(id: @inbox_id)
    contact = @account.contacts.find_by(id: @contact_id)
    if inbox.blank? || contact.blank?
      Rails.logger.warn(
        "[ConversationWorkflow] send_message_to_contact skipped missing inbox/contact " \
        "(rule_id=#{@rule.id} inbox_id=#{@inbox_id} contact_id=#{@contact_id} " \
        "inbox_found=#{inbox.present?} contact_found=#{contact.present?})"
      )
      return
    end

    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    if contact_inbox.blank?
      Rails.logger.warn(
        "[ConversationWorkflow] send_message_to_contact skipped contact_inbox blank " \
        "(rule_id=#{@rule.id} inbox_id=#{inbox.id} channel=#{inbox.channel_type} " \
        "contact_id=#{contact.id} has_phone=#{contact.phone_number.present?} " \
        "has_email=#{contact.email.present?})"
      )
      return
    end

    target_conversation = ConversationBuilder.new(
      params: {},
      contact_inbox: contact_inbox
    ).perform
    if target_conversation.blank?
      Rails.logger.warn(
        "[ConversationWorkflow] send_message_to_contact skipped conversation blank " \
        "(rule_id=#{@rule.id} contact_inbox_id=#{contact_inbox.id})"
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
    Rails.logger.warn(
      "[ConversationWorkflow] send_message_to_contact failed " \
      "(rule_id=#{@rule.id} inbox_id=#{@inbox_id} contact_id=#{@contact_id}): " \
      "#{e.class} #{e.message}"
    )
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
  end

  private

  def interpolate(template)
    return '' if template.blank?

    context = { conversation: @conversation, rule: @rule }
    template.to_s.gsub(/\{\{\s*([\w.]+)\s*\}\}/) do
      key = Regexp.last_match(1)
      resolver = TEMPLATE_VARIABLES[key]
      resolver ? resolver.call(context).to_s : Regexp.last_match(0)
    end
  end
end
