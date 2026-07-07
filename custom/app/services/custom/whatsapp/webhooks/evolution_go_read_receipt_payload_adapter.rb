# frozen_string_literal: true

class Custom::Whatsapp::Webhooks::EvolutionGoReadReceiptPayloadAdapter
  class << self
    def canonicalize_data(data, envelope_state: nil)
      return {} if data.blank?
      return data.with_indifferent_access if data.is_a?(Hash) && legacy_key_shape?(data)

      data = data.with_indifferent_access
      message_ids = Array.wrap(data[:MessageIDs] || data[:messageIds] || data[:message_ids]).map(&:to_s).compact_blank
      chat = data[:Chat] || data[:chat]
      return {} if message_ids.blank?

      {
        key: {
          id: message_ids.first,
          remoteJid: chat,
          remoteJidAlt: data[:SenderAlt] || data[:senderAlt]
        },
        message_ids: message_ids,
        timestamp: timestamp_value(data),
        receipt_state: envelope_state.presence || data[:state] || data[:State],
        receipt_type: data[:Type] || data[:type]
      }.compact.with_indifferent_access
    end

    private

    def legacy_key_shape?(data)
      key = data[:key] || data['key']
      key.is_a?(Hash) && (key[:id] || key['id']).present?
    end

    def timestamp_value(data)
      ts = data[:Timestamp] || data[:timestamp] || data[:messageTimestamp]
      return ts.to_i.to_s if ts.is_a?(Numeric)
      return Time.zone.parse(ts.to_s).to_i.to_s if ts.present?

      nil
    rescue ArgumentError, TypeError
      nil
    end
  end
end
