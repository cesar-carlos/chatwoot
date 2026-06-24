# frozen_string_literal: true

class Wavoip::Webhooks::PayloadNormalizer
  PROVIDER = :wavoip

  def initialize(payload)
    @payload = payload.to_h.with_indifferent_access
  end

  def normalize
    case event_type
    when 'CALL'
      normalize_call_event
    when 'RECORD'
      normalize_record_event
    when 'DEVICE'
      normalize_device_event
    else
      Rails.logger.warn("[WAVOIP] Unknown webhook type=#{event_type.inspect}") unless Rails.env.production?
      nil
    end
  end

  private

  attr_reader :payload

  # Official examples declare `type` twice in CALL payloads; JSON.parse keeps the last value.
  def event_type
    payload[:type].to_s.presence
  end

  def normalize_call_event
    Voice::Dto::WebhookCallEvent.new(**call_event_attributes)
  end

  def call_event_attributes
    {
      provider: PROVIDER,
      external_call_id: external_call_id_from_payload,
      action: webhook_action,
      external_status: payload[:status].to_s,
      direction: map_direction(payload[:direction]),
      from_phone: call_from_phone,
      to_phone: normalize_phone(payload[:phone]),
      peer_name: peer_display_name,
      duration_seconds: parse_duration(payload[:duration]),
      session_id: payload[:id_session],
      call_type: map_call_type(payload[:call_type]),
      record_url: nil,
      raw_type: 'CALL'
    }
  end

  def webhook_action
    payload[:action].to_s.downcase == 'create' ? :create : :update
  end

  def call_from_phone
    return normalize_phone(peer_phone) if peer_phone.present?
    return normalize_phone(payload[:phone]) if webhook_action == :create

    nil
  end

  def normalize_record_event
    Voice::Dto::WebhookCallEvent.new(
      provider: PROVIDER,
      external_call_id: external_call_id_from_payload,
      action: :update,
      external_status: 'RECORD',
      direction: nil,
      from_phone: normalize_phone(payload[:phone]),
      to_phone: nil,
      peer_name: nil,
      duration_seconds: nil,
      session_id: payload[:id_session],
      call_type: nil,
      record_url: payload[:record_url].to_s.presence,
      raw_type: 'RECORD'
    )
  end

  def normalize_device_event
    Voice::Dto::WebhookCallEvent.new(
      provider: PROVIDER,
      external_call_id: nil,
      action: :update,
      external_status: payload[:status].to_s,
      direction: nil,
      from_phone: normalize_phone(payload[:phone]),
      to_phone: nil,
      peer_name: nil,
      duration_seconds: nil,
      session_id: payload[:id_session],
      call_type: nil,
      record_url: nil,
      raw_type: 'DEVICE'
    )
  end

  def map_direction(value)
    case value.to_s.upcase
    when 'INCOMING' then :incoming
    when 'OUTGOING', 'OUTCOMING' then :outgoing
    end
  end

  def map_call_type(value)
    case value.to_s.downcase
    when 'official' then :official
    when 'unofficial' then :unofficial
    end
  end

  def peer_phone
    payload.dig(:peer, :phone) || payload.dig(:peer, 'phone')
  end

  def peer_display_name
    payload.dig(:peer, :display_name) || payload.dig(:peer, 'display_name')
  end

  def external_call_id_from_payload
    (payload[:whatsapp_call_id].presence || payload[:id]).to_s
  end

  def normalize_phone(phone)
    Wavoip::PhoneNormalizer.normalize(phone, inbox_phone: payload[:phone])
  end

  def parse_duration(value)
    return if value.blank?

    value.to_i
  end
end
