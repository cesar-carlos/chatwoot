# frozen_string_literal: true

class Wavoip::Webhooks::Dispatcher
  HANDLERS = {
    'CALL' => Wavoip::Webhooks::Handlers::CallHandler,
    'RECORD' => Wavoip::Webhooks::Handlers::RecordHandler,
    'DEVICE' => Wavoip::Webhooks::Handlers::DeviceHandler
  }.freeze

  # Avoid locking provider_config on every CALL burst; keep last_webhook_at
  # accurate within TOUCH_DEBOUNCE_SECONDS (same pattern as Evolution Go).
  TOUCH_DEBOUNCE_SECONDS = 30

  def initialize(inbox:, payload:)
    @inbox = inbox
    @payload = payload
  end

  def dispatch
    event = Wavoip::Webhooks::PayloadNormalizer.new(
      payload,
      inbox_phone: channel_phone_number
    ).normalize
    return if event.blank?

    handler_class = HANDLERS[event.raw_type]
    return if handler_class.blank?

    result = handler_class.new(inbox: inbox, event: event).perform
    touch_last_webhook_at!
    result
  end

  private

  attr_reader :inbox, :payload

  def channel_phone_number
    channel = inbox.channel
    channel.phone_number if channel.is_a?(Channel::Wavoip)
  end

  def touch_last_webhook_at!
    channel = inbox.channel
    return unless channel.is_a?(Channel::Wavoip)

    debounced = Redis::Alfred.set(
      touch_debounce_key(channel),
      true,
      nx: true,
      ex: TOUCH_DEBOUNCE_SECONDS
    )
    return unless debounced

    channel.with_lock do
      channel.reload
      config = (channel.provider_config || {}).dup
      config['last_webhook_at'] = Time.current.iso8601
      channel.update!(provider_config: config)
    end
  end

  def touch_debounce_key(channel)
    format(Redis::RedisKeys::WAVOIP_WEBHOOK_TOUCH_DEBOUNCE, channel_id: channel.id)
  end
end
