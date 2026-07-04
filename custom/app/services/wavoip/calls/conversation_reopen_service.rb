# frozen_string_literal: true

# Reopens Wavoip voice conversations for agents to pick up calls.
# Inbound calls use +pending+; outbound calls use +open+.
class Wavoip::Calls::ConversationReopenService
  def self.perform!(conversation:, status: :open)
    new(conversation: conversation, status: status).perform!
  end

  def initialize(conversation:, status: :open)
    @conversation = conversation
    @status = status.to_sym
  end

  def perform!
    return unless wavoip_inbox?
    return if conversation.muted?

    case status
    when :pending
      reopen_as_pending!
    else
      reopen_as_open!
    end
  end

  private

  attr_reader :conversation, :status

  def wavoip_inbox?
    conversation.inbox&.channel.is_a?(Channel::Wavoip)
  end

  def reopen_as_pending!
    return if conversation.pending?

    conversation.pending! if conversation.resolved? || conversation.snoozed? || conversation.open?
  end

  def reopen_as_open!
    return if conversation.open?

    conversation.open! if conversation.resolved? || conversation.snoozed? || conversation.pending?
  end
end
