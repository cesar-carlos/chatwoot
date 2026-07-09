# frozen_string_literal: true

class Custom::Whatsapp::Evolution::PresenceSyncJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, typing_on, is_private = false)
    return if ActiveModel::Type::Boolean.new.cast(is_private)

    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    Custom::Whatsapp::Evolution::PresenceSyncService.new(
      conversation: conversation,
      typing_on: ActiveModel::Type::Boolean.new.cast(typing_on)
    ).perform
  end
end
