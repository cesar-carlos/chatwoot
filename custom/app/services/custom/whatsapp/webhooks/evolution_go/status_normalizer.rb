# frozen_string_literal: true

module Custom::Whatsapp::Webhooks::EvolutionGo::StatusNormalizer
  private

  def normalize_read_receipt(data)
    data = data.with_indifferent_access
    key = data[:key] || {}
    message_ids = Array.wrap(data[:message_ids]).presence || [key[:id]].compact
    return nil if message_ids.blank?

    status = map_receipt_status(data)
    return nil if status.blank?

    remote_jid = extract_status_remote_jid(key)
    timestamp = status_timestamp(data)
    recipient_id = jid_resolver.recipient_id_for_status(remote_jid, key)

    {
      statuses: message_ids.map do |message_id|
        {
          id: message_id,
          status: status,
          timestamp: timestamp,
          recipient_id: recipient_id
        }
      end
    }
  end

  def map_receipt_status(data) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    state = (data[:receipt_state] || data[:state] || data[:State]).to_s
    type = (data[:receipt_type] || data[:Type] || data[:type]).to_s.downcase

    return nil if state.casecmp('readself').zero?

    return 'delivered' if state.casecmp('delivered').zero?
    return 'read' if state.casecmp('read').zero? || type == 'read'

    'read'
  end

  def status_timestamp(data)
    data['messageTimestamp'].presence ||
      data['timestamp'].presence ||
      parse_iso_timestamp(data['Timestamp']) ||
      Time.current.to_i
  end

  def parse_iso_timestamp(value)
    return if value.blank?

    Time.zone.parse(value.to_s).to_i
  rescue ArgumentError, TypeError
    nil
  end

  def extract_status_remote_jid(key)
    jid_resolver.resolve_message_jid(key.with_indifferent_access)
  end

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::EvolutionGo::JidResolver.new(config)
  end
end
