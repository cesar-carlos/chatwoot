# frozen_string_literal: true

class Wavoip::Webhooks::Handlers::CallUpdateHandler < Wavoip::Webhooks::Handlers::BaseHandler
  def perform
    return if event.external_call_id.blank?

    Wavoip::Calls::CallUpsertService.new(inbox: inbox, event: event).update!
  end
end
