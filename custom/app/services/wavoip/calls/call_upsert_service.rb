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
    return if inbound_incoming_blocked?

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
    call = find_call
    if call.blank?
      return if inbound_incoming_blocked?

      call = create!
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

  def apply_status!(call, broadcast:)
    mapped_status = status_mapper.to_call_status(event.external_status)
    return false if mapped_status.blank?

    call.with_lock do
      call.reload
      next false unless transition_allowed?(call, mapped_status)

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
    end

    true
  end

  def build_update_attrs(call, mapped_status)
    return nil if mapped_status == call.status && event.duration_seconds.blank?

    attrs = base_status_attrs(call, mapped_status)
    attrs[:meta] = status_meta(call, mapped_status)
    attrs
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
      broadcaster.broadcast_accepted(call)
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
end
