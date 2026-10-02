# frozen_string_literal: true

module Custom::ActionCableListener
  include Events::Types

  CONVERSATION_EVENTS = [
    MESSAGE_CREATED,
    MESSAGE_UPDATED,
    FIRST_REPLY_CREATED,
    CONVERSATION_CREATED,
    CONVERSATION_READ,
    CONVERSATION_STATUS_CHANGED,
    CONVERSATION_UPDATED,
    CONVERSATION_TYPING_ON,
    CONVERSATION_TYPING_OFF,
    ASSIGNEE_CHANGED,
    TEAM_CHANGED,
    CONVERSATION_CONTACT_CHANGED,
    CONVERSATION_MENTIONED
  ].freeze

  def notification_created(event)
    return unless notification_visible?(event.data[:notification])

    super
  end

  def notification_updated(event)
    return unless notification_visible?(event.data[:notification])

    super
  end

  private

  def broadcast(account, tokens, event_name, data)
    if CONVERSATION_EVENTS.include?(event_name)
      conversation = conversation_for_event(account, event_name, data)
      tokens = if conversation.present?
                 authorized_tokens(account, conversation, tokens)
               else
                 contact_only_tokens(account, tokens)
               end
    end

    super(account, tokens, event_name, data)
  end

  def conversation_for_event(account, event_name, data)
    display_id =
      case event_name
      when MESSAGE_CREATED, MESSAGE_UPDATED, FIRST_REPLY_CREATED
        data[:conversation_id]
      when CONVERSATION_TYPING_ON, CONVERSATION_TYPING_OFF
        data.dig(:conversation, :id)
      else
        data[:id]
      end

    account.conversations.find_by(display_id: display_id)
  end

  def authorized_tokens(account, conversation, tokens)
    Custom::Conversations::EventRecipientService.new(
      account: account,
      conversation: conversation,
      tokens: tokens
    ).perform
  end

  def contact_only_tokens(account, tokens)
    account_user_tokens = account.users.where(pubsub_token: tokens).pluck(:pubsub_token)
    tokens - account_user_tokens
  end

  def notification_visible?(notification)
    Custom::Notification::AccessibleScope.for(user: notification.user, account: notification.account).exists?(notification.id)
  end
end
