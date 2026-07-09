# frozen_string_literal: true

class Custom::Whatsapp::Evolution::TypingListener < BaseListener
  def conversation_typing_on(event)
    enqueue_presence(event, typing_on: true)
  end

  def conversation_typing_off(event)
    enqueue_presence(event, typing_on: false)
  end

  private

  def enqueue_presence(event, typing_on:)
    conversation = event.data[:conversation]
    return if conversation.blank?
    return unless evolution_inbox?(conversation)
    return if ActiveModel::Type::Boolean.new.cast(event.data[:is_private])

    Custom::Whatsapp::Evolution::PresenceSyncJob.perform_later(
      conversation.id,
      typing_on,
      false
    )
  end

  def evolution_inbox?(conversation)
    channel = conversation.inbox&.channel
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'
  end
end
