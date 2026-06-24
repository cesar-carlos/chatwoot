# frozen_string_literal: true

class Wavoip::Calls::CallUpsertService
  def initialize(
    inbox:,
    event:,
    status_mapper: Wavoip::Calls::StatusMapper.new,
    broadcaster: nil
  )
    @inbox = inbox
    @event = event
    @status_mapper = status_mapper
    @broadcaster = broadcaster || Wavoip::Calls::Broadcaster.new(inbox: inbox)
    @status_applier = Wavoip::Calls::CallStatusApplier.new(
      inbox: inbox,
      event: event,
      status_mapper: status_mapper,
      broadcaster: @broadcaster
    )
  end

  def create!
    return log_skip_create('voice disabled') unless inbox.channel.voice_enabled?
    return log_skip_create('inbound blocked') if inbound_incoming_blocked?
    return log_skip_create('missing or inbox peer phone') if invalid_contact_phone_for_create?

    existing = find_call
    if existing
      status_applier.apply!(existing, broadcast: true)
      return existing
    end

    call = Wavoip::Calls::ConversationLinker.link!(inbox: inbox, event: event)
    mark_webhook_verified!
    status_applier.apply!(call, broadcast: true)
    call
  end

  def update!
    return log_skip_update('voice disabled') unless inbox.channel.voice_enabled?

    call = resolve_call_for_update
    return if call.blank?
    return call unless status_applier.apply!(call, broadcast: true)

    call
  end

  private

  attr_reader :inbox, :event, :status_mapper, :broadcaster, :status_applier

  def resolve_call_for_update
    call = find_call
    return call if call.present?
    return if inbound_incoming_blocked?

    call = create!
    call = handled_remotely_stub_service.perform if call.blank? && handled_remotely_event?
    log_handled_remotely_missing_call if call.blank? && handled_remotely_event?
    call
  end

  def find_call
    Wavoip::Calls::CallLookup.find(inbox: inbox, provider_call_id: event.external_call_id)
  end

  def inbound_incoming_blocked?
    event.direction == :incoming && !inbox.channel.inbound_calls_enabled?
  end

  def invalid_contact_phone_for_create?
    phone = Wavoip::Calls::ConversationLinker.contact_phone_for(
      event,
      inbox_phone: inbox.channel.phone_number
    )
    return true if phone.blank?

    inbox_digits = inbox.channel.phone_number.to_s.gsub(/\D/, '')
    phone_digits = phone.to_s.gsub(/\D/, '')
    phone_digits.present? && phone_digits == inbox_digits
  end

  def handled_remotely_event?
    event.external_status.to_s.upcase == 'HANDLED_REMOTELY'
  end

  def handled_remotely_stub_service
    Wavoip::Calls::HandledRemotelyStubService.new(
      inbox: inbox,
      event: event,
      broadcaster: broadcaster,
      invalid_contact_phone: method(:invalid_contact_phone_for_create?)
    )
  end

  def mark_webhook_verified!
    channel = inbox.channel
    return unless channel.is_a?(Channel::Wavoip)
    return if channel.webhook_verified?

    config = (channel.provider_config || {}).dup
    config['webhook_verified_at'] = Time.current.iso8601
    channel.update!(provider_config: config)
  end

  def log_skip_create(reason)
    Rails.logger.warn(
      "[WAVOIP] Skipped create: #{reason} inbox_id=#{inbox.id} call_id=#{event.external_call_id}"
    )
    nil
  end

  def log_skip_update(reason)
    Rails.logger.warn("[WAVOIP] Skipped update: #{reason} inbox_id=#{inbox.id}")
    nil
  end

  def log_handled_remotely_missing_call
    Rails.logger.warn(
      "[WAVOIP] HANDLED_REMOTELY without call row inbox_id=#{inbox.id} call_id=#{event.external_call_id}"
    )
  end
end
