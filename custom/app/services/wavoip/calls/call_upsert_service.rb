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
  end

  def create!
    unless inbox.channel.voice_enabled?
      Rails.logger.warn("[WAVOIP] Skipped create: voice disabled inbox_id=#{inbox.id}")
      return
    end
    if inbound_incoming_blocked?
      Rails.logger.warn("[WAVOIP] Skipped create: inbound blocked inbox_id=#{inbox.id}")
      return
    end
    if invalid_contact_phone_for_create?
      Rails.logger.warn(
        "[WAVOIP] Skipped create: missing or inbox peer phone inbox_id=#{inbox.id} call_id=#{event.external_call_id}"
      )
      return
    end

    existing = find_call
    if existing
      apply_status!(existing, broadcast: true)
      return existing
    end

    call = Wavoip::Calls::ConversationLinker.link!(inbox: inbox, event: event)
    mark_webhook_verified!
    apply_status!(call, broadcast: true)
    call
  end

  def update!
    unless inbox.channel.voice_enabled?
      Rails.logger.warn("[WAVOIP] Skipped update: voice disabled inbox_id=#{inbox.id}")
      return
    end

    call = find_call
    if call.blank?
      return if inbound_incoming_blocked?

      call = create!
      if call.blank? && event.external_status.to_s.upcase == 'HANDLED_REMOTELY'
        call = create_handled_remotely_stub!
        if call.blank?
          Rails.logger.warn(
            "[WAVOIP] HANDLED_REMOTELY without call row inbox_id=#{inbox.id} call_id=#{event.external_call_id}"
          )
        end
      end
      return if call.blank?
    end

    return call unless apply_status!(call, broadcast: true)

    call
  end

  private

  attr_reader :inbox, :event, :status_mapper, :broadcaster

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

  def apply_status!(call, broadcast:)
    mapped_status = status_mapper.to_call_status(event.external_status)
    if mapped_status.blank?
      Rails.logger.warn(
        "[WAVOIP] Ignored status inbox_id=#{inbox.id} call_id=#{event.external_call_id} " \
        "external_status=#{event.external_status}"
      )
      return false
    end

    applied = call.with_lock do
      call.reload
      unless transition_allowed?(call, mapped_status)
        Rails.logger.warn(
          "[WAVOIP] Blocked transition inbox_id=#{inbox.id} call_id=#{event.external_call_id} " \
          "from=#{call.status} to=#{mapped_status}"
        )
        next false
      end

      attrs = build_update_attrs(call, mapped_status)
      next false if attrs.blank?

      call.update!(attrs)
      Voice::CallMessageBuilder.new(call).update_status!(
        status: call.status,
        agent: call.accepted_by_agent,
        duration_seconds: call.duration_seconds
      )
      update_conversation(call)
      emit_broadcasts(call, mapped_status) if broadcast
      true
    end

    applied == true
  end

  def build_update_attrs(call, mapped_status)
    effective_status = contextual_terminal_status(call, mapped_status)
    return nil if effective_status == call.status && event.duration_seconds.blank?

    attrs = base_status_attrs(call, effective_status)
    attrs[:meta] = status_meta(call, effective_status)
    attrs
  end

  # Wavoip sends ENDED for both answered and unanswered calls.
  # If the call never reached in_progress, treat it as no_answer.
  def contextual_terminal_status(call, mapped_status)
    return mapped_status unless mapped_status == 'completed'
    return mapped_status if event.external_status.to_s.upcase == 'HANDLED_REMOTELY'
    return mapped_status if call.in_progress? || call.started_at.present?

    'no_answer'
  end

  def base_status_attrs(call, mapped_status)
    attrs = { status: mapped_status }
    attrs[:duration_seconds] = event.duration_seconds if event.duration_seconds.present?
    attrs[:started_at] = Time.current if mapped_status == 'in_progress' && call.started_at.blank?

    end_reason = status_mapper.end_reason_for(event.external_status)
    attrs[:end_reason] = end_reason if end_reason.present?
    attrs
  end

  def status_meta(call, mapped_status)
    base_meta = (call.meta || {}).merge('wavoip_status' => event.external_status)
    return base_meta.merge('ended_at' => Time.zone.now.to_i) if status_mapper.terminal?(mapped_status)

    base_meta
  end

  def transition_allowed?(call, mapped_status)
    return true unless call.terminal?

    return false if mapped_status == 'ringing'
    return false if mapped_status == 'in_progress' && call.status != mapped_status

    true
  end

  def emit_broadcasts(call, mapped_status)
    if mapped_status == 'ringing' && call.incoming?
      broadcaster.broadcast_incoming(call)
    elsif mapped_status == 'in_progress'
      if call.incoming?
        broadcaster.broadcast_agent_accepted(
          call,
          accepted_by_agent_id: call.accepted_by_agent_id
        )
      else
        broadcaster.broadcast_accepted(call)
      end
    elsif status_mapper.terminal?(mapped_status)
      broadcaster.broadcast_ended(call)
    end
  end

  def update_conversation(call)
    call.conversation.update!(
      additional_attributes: (call.conversation.additional_attributes || {}).merge(
        'call_status' => call.display_status,
        'call_direction' => call.direction_label
      )
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

  def create_handled_remotely_stub!
    return if event.external_call_id.blank?
    return if invalid_contact_phone_for_create?

    call = Wavoip::Calls::ConversationLinker.link_inbound!(inbox: inbox, event: event)
    call.update!(
      status: 'completed',
      end_reason: 'handled_remotely',
      meta: (call.meta || {}).merge(
        'wavoip_status' => event.external_status,
        'ended_at' => Time.zone.now.to_i
      )
    )
    Voice::CallMessageBuilder.new(call).update_status!(
      status: call.status,
      agent: nil,
      duration_seconds: call.duration_seconds
    )
    update_conversation(call)
    broadcaster.broadcast_ended(call)
    mark_webhook_verified!
    call
  rescue StandardError => e
    Rails.logger.warn(
      "[WAVOIP] HANDLED_REMOTELY stub failed inbox_id=#{inbox.id} " \
      "call_id=#{event.external_call_id}: #{e.message}"
    )
    nil
  end
end
