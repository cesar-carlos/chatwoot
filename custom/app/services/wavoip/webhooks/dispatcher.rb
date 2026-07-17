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

    result = handler_class.new(inbox: inbox, event: event).perform
    touch_last_webhook_at!
    result
  end

  private

  attr_reader :inbox, :payload

  def touch_last_webhook_at!
    channel = inbox.channel
    return unless channel.is_a?(Channel::Wavoip)

    channel.with_lock do
      channel.reload
      config = (channel.provider_config || {}).dup
      config['last_webhook_at'] = Time.current.iso8601
      channel.update!(provider_config: config)
    end
  end
end
