# frozen_string_literal: true

module Custom::Whatsapp::Webhooks::EvolutionGo::StatusNormalizer
  private

  def normalize_read_receipt(data)
    data = data.with_indifferent_access
    key = data[:key] || {}
    message_id = key[:id]
    remote_jid = key[:remoteJid] || key[:remoteJidAlt]
    return nil if message_id.blank?

    {
      statuses: [
        {
          id: message_id,
          status: 'read',
          timestamp: status_timestamp(data),
          recipient_id: phone_from_jid(remote_jid)
        }
      ]
    }
  end

  def status_timestamp(data)
    data['messageTimestamp'].presence || data['timestamp'].presence || Time.current.to_i
  end
end
