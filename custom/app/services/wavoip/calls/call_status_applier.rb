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

    deferred = []
    applied = call.with_lock do
      apply_locked!(call, mapped_status, broadcast: broadcast, deferred: deferred)
    end
    run_deferred!(deferred) if applied == true && broadcast
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

  def apply_locked!(call, mapped_status, broadcast:, deferred:)
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
    queue_broadcasts!(call, mapped_status, deferred) if broadcast
    true
  end

  def persist_status!(call, attrs)
    # Prefer ACTIVE; also cover completed when ACTIVE was skipped but join
    # already wrote JoiningAgentCache (GAP-02 webhook fallback).
    if attrs[:status].in?(%w[in_progress completed])
      assign_joining_agent_if_needed!(call)
    end
    call.update!(attrs)
    Wavoip::Calls::CallFinalizer.sync_message_and_conversation!(call)
  end

  def build_update_attrs(call, mapped_status)
    effective_status = contextual_terminal_status(call, mapped_status)
    attrs = base_status_attrs(call, effective_status)
    attrs[:meta] = status_meta(call, effective_status)
    return nil if attrs_unchanged?(call, attrs)

    attrs
  end

  def attrs_unchanged?(call, attrs)
    return false unless scalar_attrs_unchanged?(call, attrs)

    meta_unchanged?(call, attrs[:meta] || {})
  end

  def scalar_attrs_unchanged?(call, attrs)
    status_unchanged?(call, attrs) &&
      duration_unchanged?(call, attrs) &&
      end_reason_unchanged?(call, attrs) &&
      started_at_unchanged?(call, attrs)
  end

  def status_unchanged?(call, attrs)
    attrs[:status] == call.status
  end

  def duration_unchanged?(call, attrs)
    attrs[:duration_seconds].blank? || attrs[:duration_seconds] == call.duration_seconds
  end

  def end_reason_unchanged?(call, attrs)
    attrs[:end_reason].blank? || attrs[:end_reason] == call.end_reason
  end

  def started_at_unchanged?(call, attrs)
    attrs[:started_at].blank? || call.started_at.present?
  end

  def meta_unchanged?(call, proposed_meta)
    current_meta = call.meta || {}
    proposed_meta.all? { |key, value| current_meta[key] == value }
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
    base_meta['ended_at'] ||= Time.zone.now.to_i if status_mapper.terminal?(mapped_status)

    base_meta
  end

  def transition_allowed?(call, mapped_status)
    return true unless call.terminal?
    return false if mapped_status == 'ringing'
    return false if mapped_status == 'in_progress'
    return false if status_mapper.terminal?(mapped_status) && mapped_status != call.status

    true
  end

  def queue_broadcasts!(call, mapped_status, deferred)
    case mapped_status
    when 'ringing' then queue_ringing_broadcasts!(call, deferred)
    when 'in_progress' then queue_in_progress_broadcasts!(call, deferred)
    else queue_terminal_broadcasts!(call, mapped_status, deferred) if status_mapper.terminal?(mapped_status)
    end
  end

  def queue_ringing_broadcasts!(call, deferred)
    deferred << -> { Wavoip::Calls::StaleCallTimeoutScheduler.new(call: call.reload).schedule }
    return unless call.incoming?

    deferred << -> { broadcaster.broadcast_incoming(call.reload) }
    deferred << -> { Wavoip::Calls::RingEscalationScheduler.new(call: call.reload).schedule }
  end

  def queue_in_progress_broadcasts!(call, deferred)
    deferred << lambda {
      Wavoip::Calls::StaleCallTimeoutScheduler.new(call: call.reload).schedule_in_progress_safety_net
    }
    deferred << -> { broadcast_in_progress(call.reload) }
  end

  def queue_terminal_broadcasts!(call, mapped_status, deferred)
    deferred << -> { broadcaster.broadcast_ended(call.reload) } unless defer_outbound_ended_broadcast?(call)
    deferred << -> { schedule_direct_recording_fetch(call.reload) } if mapped_status == 'completed'
  end

  def run_deferred!(deferred)
    deferred.each(&:call)
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
