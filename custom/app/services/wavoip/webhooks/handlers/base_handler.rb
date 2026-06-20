# frozen_string_literal: true

class Wavoip::Webhooks::Handlers::BaseHandler
  def initialize(inbox:, event:)
    @inbox = inbox
    @event = event
  end

  private

  attr_reader :inbox, :event
end
