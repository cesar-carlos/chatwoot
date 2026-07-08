# frozen_string_literal: true

# Meta can deliver the outbound `connect` webhook (with SDP answer) in the tiny
# window between initiate_call returning and Call.create! committing. Re-process
# the connect payload after a short delay until the row exists.
class Whatsapp::RetryOutboundConnectJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 5
  RETRY_DELAY = 2.seconds

  def perform(inbox_id, payload, attempt = 1)
    inbox = Inbox.find_by(id: inbox_id)
    return unless inbox&.channel&.voice_enabled?

    payload = payload.with_indifferent_access
    call = Call.whatsapp.find_by(provider_call_id: payload[:id])

    unless call
      if attempt >= MAX_ATTEMPTS
        Rails.logger.warn "[WHATSAPP CALL] Outbound connect gave up for unknown call #{payload[:id]}"
        return
      end

      self.class.set(wait: RETRY_DELAY).perform_later(inbox_id, payload.to_h, attempt + 1)
      return
    end

    Whatsapp::IncomingCallService.new(inbox: inbox, params: { calls: [payload] }).perform
  end
end
