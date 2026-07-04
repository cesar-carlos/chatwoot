# frozen_string_literal: true

class Wavoip::Calls::RecordingPolicy
  BLOCKED_STATUSES = %w[DISABLED EMPTY_RECORDING].freeze
  PENDING_STATUSES = %w[RECORDING MIXING].freeze
  READY_STATUSES = %w[READY].freeze
  KNOWN_STATUSES = (BLOCKED_STATUSES + PENDING_STATUSES + READY_STATUSES).freeze

  def self.attachable?(inbox:, record_url:, record_status: nil, call: nil)
    new(inbox: inbox, record_url: record_url, record_status: record_status, call: call).attachable?
  end

  def self.recording_feature_enabled?(inbox:)
    channel = inbox.channel
    channel.is_a?(Channel::Wavoip) && channel.call_recording_enabled?
  end

  def initialize(inbox:, record_url:, record_status: nil, call: nil)
    @inbox = inbox
    @record_url = record_url
    @record_status = record_status
    @call = call
  end

  def attachable?
    return false unless self.class.recording_feature_enabled?(inbox: inbox)
    return false if record_url.blank?
    return false if blocked_status?
    return false if pending_status?
    return false unless call_completed?
    return false unless ready_status?

    true
  end

  def persist_status_only?
    return false unless self.class.recording_feature_enabled?(inbox: inbox)
    return false if record_url.blank?
    return false if blocked_status?

    pending_status?
  end

  private

  attr_reader :inbox, :record_url, :record_status, :call

  def blocked_status?
    BLOCKED_STATUSES.include?(normalized_status)
  end

  def pending_status?
    PENDING_STATUSES.include?(normalized_status)
  end

  def ready_status?
    status = normalized_status
    return true if status.blank?

    if READY_STATUSES.include?(status)
      true
    else
      log_unknown_status if status.present?
      false
    end
  end

  def call_completed?
    return true if call.blank?

    call.status == 'completed'
  end

  def normalized_status
    record_status.to_s.upcase.presence
  end

  def log_unknown_status
    return if KNOWN_STATUSES.include?(normalized_status)

    Rails.logger.warn(
      "[WAVOIP] Unknown record_status=#{normalized_status} inbox_id=#{inbox.id} " \
      "call_id=#{call&.id}"
    )
  end
end
