# frozen_string_literal: true

class Wavoip::Webhooks::Handlers::CallCreateHandler < Wavoip::Webhooks::Handlers::BaseHandler
  def perform
    return if event.external_call_id.blank?

    Wavoip::Calls::CallUpsertService.new(inbox: inbox, event: event).create!
  end
end
