# frozen_string_literal: true

# FORK: skip WhatsApp group conversations (@g.us) for automation rules.
module Custom::AutomationRuleListener
  def message_created(event)
    return if whatsapp_group_conversation?(event.data[:message]&.conversation)

    super
  end

  private

  def process_conversation_event(event, event_name)
    return if whatsapp_group_conversation?(event.data[:conversation])

    super
  end

  def whatsapp_group_conversation?(conversation)
    conversation&.contact_inbox&.source_id.to_s.end_with?('@g.us')
  end
end
