# frozen_string_literal: true

class Wavoip::Webhooks::Dispatcher
  HANDLERS = {
    'CALL' => Wavoip::Webhooks::Handlers::CallHandler,
    'RECORD' => Wavoip::Webhooks::Handlers::RecordHandler,
    'DEVICE' => Wavoip::Webhooks::Handlers::DeviceHandler
  }.freeze

  def initialize(inbox:, payload:)
    @inbox = inbox
    @payload = payload
  end

  def dispatch
    event = Wavoip::Webhooks::PayloadNormalizer.new(payload).normalize
    return if event.blank?

    handler_class = HANDLERS[event.raw_type]
    return if handler_class.blank?

    handler_class.new(inbox: inbox, event: event).perform
  end

  private

  attr_reader :inbox, :payload
end
