# frozen_string_literal: true

class Wavoip::Calls::StatusMapper
  RINGING = %w[INCOMING_RING OUTGOING_RING OUTGOING_CALLING CONNECTING CALLING].freeze
  FAILED = %w[REJECTED FAILED CONNECTION_LOST].freeze
  IGNORE = %w[REMOTE_CALL_IN_PROGRESS].freeze

  DIRECT_STATUS_MAP = {
    'ACTIVE' => 'in_progress',
    'ENDED' => 'completed',
    'HANDLED_REMOTELY' => 'completed',
    'NOT_ANSWERED' => 'no_answer'
  }.freeze

  def to_call_status(external_status)
    status = external_status.to_s.upcase
    return if status.blank? || IGNORE.include?(status)
    return 'ringing' if RINGING.include?(status)
    return 'failed' if FAILED.include?(status)

    DIRECT_STATUS_MAP[status]
  end

  def terminal?(call_status)
    Call::TERMINAL_STATUSES.include?(call_status.to_s)
  end

  def end_reason_for(external_status)
    return 'handled_remotely' if external_status.to_s.upcase == 'HANDLED_REMOTELY'

    case external_status.to_s.upcase
    when 'REJECTED' then 'rejected'
    when 'FAILED', 'CONNECTION_LOST' then 'failed'
    when 'NOT_ANSWERED' then 'no_answer'
    end
  end
end
