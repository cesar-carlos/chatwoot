# frozen_string_literal: true

class Wavoip::Calls::ClearIncomingNotificationsService
  pattr_initialize [:call!]

  def perform
    return if conversation.blank?

    conversation.notifications
                .voice_call_incoming
                .find_each(&:destroy!)
  end

  private

  def conversation
    @conversation ||= call.conversation
  end
end
