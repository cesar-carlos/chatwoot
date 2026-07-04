# frozen_string_literal: true

class Wavoip::Calls::CallStatusApplier
  def initialize(inbox:, event:, status_mapper:, broadcaster:)
    @inbox = inbox
    @event = event
    @status_mapper = status_mapper
    @broadcaster = broadcaster
  end

  def apply!(call, broadcast:)
    mapped_status = mapped_status_for_event
    return false unless mapped_status

    applied = call.with_lock { apply_locked!(call, mapped_status, broadcast: broadcast) }
    applied == true
  end

  private

  attr_reader :inbox, :event, :status_mapper, :broadcaster

  def mapped_status_for_event
    mapped_status = status_mapper.to_call_status(event.external_status)
    return mapped_status if mapped_status.present?

    Rails.logger.warn(
      "[WAVOIP] Ignored status inbox_id=#{inbox.id} call_id=#{event.external_call_id} " \
      "external_status=#{event.external_status}"
    )
    nil
  end

  def apply_locked!(call, mapped_status, broadcast:)
    unless transition_allowed?(call, mapped_status)
      Rails.logger.warn(
        "[WAVOIP] Blocked transition inbox_id=#{inbox.id} call_id=#{event.external_call_id} " \
        "from=#{call.status} to=#{mapped_status}"
      )
      return false
    end

    attrs = build_update_attrs(call, mapped_status)
    return false if attrs.blank?

    persist_status!(call, attrs)
    emit_broadcasts(call, mapped_status) if broadcast
    true
  end

  def persist_status!(call, attrs)
    assign_joining_agent_if_needed!(call) if attrs[:status] == 'in_progress'
    call.update!(attrs)
    Wavoip::Calls::CallFinalizer.sync_message_and_conversation!(call)
  end

  def build_update_attrs(call, mapped_status)
    effective_status = contextual_terminal_status(call, mapped_status)
    return nil if effective_status == call.status && event.duration_seconds.blank?

    attrs = base_status_attrs(call, effective_status)
    attrs[:meta] = status_meta(call, effective_status)
    attrs
  end

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
    base_meta['record_status'] = event.record_status if event.record_status.present?
    return base_meta.merge('ended_at' => Time.zone.now.to_i) if status_mapper.terminal?(mapped_status)

    base_meta
  end

  def transition_allowed?(call, mapped_status)
    return true unless call.terminal?
    return false if mapped_status == 'ringing'
    return false if mapped_status == 'in_progress'
    return false if status_mapper.terminal?(mapped_status) && mapped_status != call.status

    true
  end

  def emit_broadcasts(call, mapped_status)
    if mapped_status == 'ringing'
      Wavoip::Calls::StaleCallTimeoutScheduler.new(call: call).schedule
      if call.incoming?
        broadcaster.broadcast_incoming(call)
        Wavoip::Calls::RingEscalationScheduler.new(call: call).schedule
      end
    elsif mapped_status == 'in_progress'
      broadcast_in_progress(call)
    elsif status_mapper.terminal?(mapped_status)
      broadcaster.broadcast_ended(call) unless defer_outbound_ended_broadcast?(call)
      schedule_direct_recording_fetch(call) if mapped_status == 'completed'
    end
  end

  def schedule_direct_recording_fetch(call)
    return unless Wavoip::Calls::RecordingPolicy.recording_feature_enabled?(inbox: inbox)

    Wavoip::FetchDirectRecordingJob
      .set(wait: Wavoip::FetchDirectRecordingJob::INITIAL_DELAY)
      .perform_later(call.id)
  end

  def defer_outbound_ended_broadcast?(call)
    call.outgoing? && call.started_at.blank?
  end

  def assign_joining_agent_if_needed!(call)
    return unless call.incoming?
    return if call.accepted_by_agent_id.present?

    Wavoip::Calls::AssignAcceptedAgentService.new(call: call).perform!
    call.reload
  end

  def broadcast_in_progress(call)
    if call.incoming?
      broadcaster.broadcast_agent_accepted(
        call,
        accepted_by_agent_id: call.accepted_by_agent_id
      )
    else
      broadcaster.broadcast_accepted(call)
    end
  end
end
