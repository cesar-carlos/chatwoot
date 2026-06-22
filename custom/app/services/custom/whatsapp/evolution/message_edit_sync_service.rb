# frozen_string_literal: true

class Custom::Whatsapp::Evolution::MessageEditSyncService
  EDITED_PREFIX = "Edited message:\n\n"

  pattr_initialize [:channel!, :data!]

  def perform
    payload = data.with_indifferent_access
    key = (payload[:key] || {}).with_indifferent_access
    body = extract_edited_body(payload)
    return if key[:id].blank? || body.blank?

    original = channel.inbox.messages.find_by(source_id: key[:id])
    return create_edited_message(key, body, original) if original.blank?

    update_original!(original, body)
  end

  private

  def extract_edited_body(payload)
    edited = payload[:editedMessage] || payload[:message] || {}
    edited = edited.with_indifferent_access
    edited[:conversation] ||
      edited.dig(:extendedTextMessage, :text) ||
      edited.dig(:imageMessage, :caption) ||
      edited.dig(:videoMessage, :caption) ||
      edited.dig(:documentMessage, :caption)
  end

  def update_original!(message, body)
    message.update!(content: "#{EDITED_PREFIX}#{body}")
  end

  def create_edited_message(key, body, original)
    envelope = {
      event: 'MESSAGES_UPSERT',
      instance: channel.provider_config['instance_name'],
      data: build_upsert_payload(key, body, original)
    }
    normalized = Custom::Whatsapp::Webhooks::EvolutionNormalizer.new(
      channel: channel,
      envelope: envelope
    ).perform
    return if normalized.blank?

    Whatsapp::IncomingMessageService.new(
      inbox: channel.inbox,
      params: normalized.merge(phone_number: channel.phone_number)
    ).perform
  end

  def build_upsert_payload(key, body, original)
    remote_jid = key[:remoteJid].presence || original&.content_attributes&.dig('evolution_remote_jid')
    {
      key: {
        id: "#{key[:id]}-edited-#{Time.current.to_i}",
        fromMe: key[:fromMe] == true,
        remoteJid: remote_jid,
        participant: key[:participant]
      }.compact,
      pushName: original&.sender&.name,
      messageType: 'conversation',
      message: { conversation: "#{EDITED_PREFIX}#{body}" },
      messageTimestamp: Time.current.to_i
    }
  end
end
