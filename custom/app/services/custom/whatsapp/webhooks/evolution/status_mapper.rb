# frozen_string_literal: true

module Custom::Whatsapp::Webhooks::Evolution::StatusMapper
  private

  def normalize_status(data)
    data = data.with_indifferent_access
    return normalize_evolution_status_payload(data) if evolution_status_payload?(data)

    normalize_baileys_status_payload(data)
  end

  def evolution_status_payload?(data)
    data[:keyId].present?
  end

  def normalize_evolution_status_payload(data)
    status_value = data[:status]
    return nil if data[:keyId].blank? || status_value.blank?

    build_status_hash(
      id: data[:keyId],
      status: map_status(status_value),
      remote_jid: data[:remoteJid],
      timestamp: status_timestamp(data),
      key: nil
    )
  end

  def normalize_baileys_status_payload(data)
    key = data[:key] || {}
    update = data[:update] || {}
    status_code = update[:status]
    message_id = key[:id]
    return nil if message_id.blank? || status_code.nil?

    build_status_hash(
      id: message_id,
      status: map_status(status_code),
      remote_jid: key[:remoteJid],
      timestamp: status_timestamp(data),
      key: key
    )
  end

  def build_status_hash(id:, status:, remote_jid:, timestamp:, key: nil)
    {
      statuses: [
        {
          id: id,
          status: status,
          timestamp: timestamp.to_s,
          recipient_id: jid_resolver.recipient_id_for_status(remote_jid, key)
        }
      ]
    }
  end

  def status_timestamp(data)
    data['messageTimestamp'].presence || data['timestamp'].presence || Time.current.to_i
  end

  def map_status(code)
    return map_status_string(code) if code.is_a?(String) && code.match?(/[A-Za-z]/)

    case code.to_i
    when 3 then 'delivered'
    when 4, 5 then 'read'
    when 0 then 'failed'
    else 'sent'
    end
  end

  def map_status_string(status)
    case status.to_s.upcase
    when 'DELIVERY_ACK' then 'delivered'
    when 'READ', 'PLAYED' then 'read'
    when 'ERROR' then 'failed'
    else 'sent'
    end
  end
end
