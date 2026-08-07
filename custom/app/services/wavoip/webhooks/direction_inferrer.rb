# frozen_string_literal: true

# Wavoip's CALL webhook direction is unreliable on its own: the explicit
# `direction` field can be missing, and even when present it can disagree
# with the inbox/caller/receiver phone numbers (observed in live payloads
# where the inbox itself is the caller but `direction` still says INCOMING).
# This isolates the multi-heuristic inference so it can be tested against
# fixtures independently of the rest of the payload parsing.
class Wavoip::Webhooks::DirectionInferrer
  def initialize(payload:, webhook_action:, external_call_id: nil, inbox_phone: nil)
    @payload = payload
    @webhook_action = webhook_action
    @external_call_id = external_call_id
    @inbox_phone = inbox_phone
  end

  def infer
    return :outgoing if inbox_is_caller?

    from_endpoints = infer_direction_from_caller_receiver
    # Prefer caller/receiver geometry over an explicit (often wrong) direction
    # when both are present and disagree.
    return from_endpoints if from_endpoints.present?

    explicit = map_direction(payload[:direction])
    return explicit if explicit.present?

    infer_direction_from_status(payload[:status])
  end

  private

  attr_reader :payload, :webhook_action, :external_call_id, :inbox_phone

  # Highest-confidence signal: the inbox's own number placed the call. Wins
  # over an explicit (but wrong) `direction: INCOMING` from the payload.
  def inbox_is_caller?
    inbox_digits = inbox_digits_for_compare
    caller_digits = phone_digits(payload[:caller])
    inbox_digits.present? && caller_digits.present? && inbox_digits == caller_digits
  end

  def map_direction(value)
    case value.to_s.upcase
    when 'INCOMING' then :incoming
    when 'OUTGOING', 'OUTCOMING' then :outgoing
    else
      log_unknown_direction if value.blank? && webhook_action == :create
      nil
    end
  end

  def infer_direction_from_caller_receiver
    inbox_digits = inbox_digits_for_compare
    return nil if inbox_digits.blank?

    direction_from_endpoints(inbox_digits)
  end

  # Prefer payload phone, fall back to the channel number resolved by the
  # webhook controller (live payloads often omit `phone`).
  def inbox_digits_for_compare
    phone_digits(payload[:phone].presence || inbox_phone)
  end

  def direction_from_endpoints(inbox_digits)
    caller_digits = phone_digits(payload[:caller])
    receiver_digits = phone_digits(payload[:receiver])

    return :outgoing if outgoing_from_endpoints?(inbox_digits, caller_digits, receiver_digits)
    return :incoming if incoming_from_endpoints?(inbox_digits, caller_digits, receiver_digits)

    nil
  end

  def outgoing_from_endpoints?(inbox_digits, caller_digits, receiver_digits)
    caller_digits == inbox_digits && receiver_digits.present? && receiver_digits != inbox_digits
  end

  def incoming_from_endpoints?(inbox_digits, caller_digits, receiver_digits)
    receiver_digits == inbox_digits && caller_digits.present? && caller_digits != inbox_digits
  end

  def infer_direction_from_status(status)
    case status.to_s.upcase
    when 'OUTGOING_RING', 'OUTGOING_CALLING', 'OUTCOMING_RING', 'OUTCOMING_CALLING'
      :outgoing
    when 'INCOMING_RING'
      :incoming
    end
  end

  def phone_digits(value)
    value.to_s.gsub(/\D/, '')
  end

  def log_unknown_direction
    return if Rails.env.production?

    Rails.logger.warn("[WAVOIP] CALL CREATE missing direction call_id=#{external_call_id}")
  end
end
