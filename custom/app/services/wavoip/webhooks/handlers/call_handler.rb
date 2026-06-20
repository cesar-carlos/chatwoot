# frozen_string_literal: true

class Wavoip::Webhooks::Handlers::CallHandler < Wavoip::Webhooks::Handlers::BaseHandler
  def perform
    if event.create?
      Wavoip::Webhooks::Handlers::CallCreateHandler.new(inbox: inbox, event: event).perform
    else
      Wavoip::Webhooks::Handlers::CallUpdateHandler.new(inbox: inbox, event: event).perform
    end
  end
end
