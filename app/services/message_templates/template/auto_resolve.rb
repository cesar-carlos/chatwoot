class MessageTemplates::Template::AutoResolve
  pattr_initialize [:conversation!, { message: nil }]

  def perform
    # FORK: optional message override for conversation workflow rules
    return if resolve_message_content.blank?

    if within_messaging_window?
      conversation.messages.create!(auto_resolve_message_params)
    else
      create_auto_resolve_not_sent_activity_message
    end
  end

  private

  delegate :contact, :account, to: :conversation
  delegate :inbox, to: :message

  def within_messaging_window?
    conversation.can_reply?
  end

  def create_auto_resolve_not_sent_activity_message
    content = I18n.t('conversations.activity.auto_resolve.not_sent_due_to_messaging_window')
    activity_message_params = {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    }
    ::Conversations::ActivityMessageJob.perform_later(conversation, activity_message_params) if content
  end

  def auto_resolve_message_params
    {
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :template,
      content: resolve_message_content
    }
  end

  def resolve_message_content
    @message.presence || account.auto_resolve_message
  end
end

# FORK: skip auto-resolve template on voice-only inboxes
MessageTemplates::Template::AutoResolve.prepend_mod_with('MessageTemplates::Template::AutoResolve')
