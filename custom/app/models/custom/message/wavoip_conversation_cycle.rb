# frozen_string_literal: true

# Wavoip voice calls reuse the contact's conversation and reopen as "pending"
# (inbound) or "open" (outbound) so agents can act on the thread.
module Custom::Message::WavoipConversationCycle
  private

  def reopen_conversation
    return super unless wavoip_voice_call_message?

    apply_wavoip_voice_call_conversation_status!
  end

  def wavoip_voice_call_message?
    voice_call? && conversation.inbox&.channel.is_a?(Channel::Wavoip)
  end

  def apply_wavoip_voice_call_conversation_status!
    return if history_import_message?

    target_status = incoming? ? :pending : :open
    Wavoip::Calls::ConversationReopenService.perform!(
      conversation: conversation,
      status: target_status
    )
  end
end
