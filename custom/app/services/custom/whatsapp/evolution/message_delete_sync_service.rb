# frozen_string_literal: true

class Custom::Whatsapp::Evolution::MessageDeleteSyncService
  pattr_initialize [:channel!, :data!]

  def perform
    key = extract_key
    return if key.blank? || key[:id].blank?

    message = find_message(key[:id])
    return if message.blank?

    soft_delete!(message)
  end

  private

  def extract_key
    payload = data.with_indifferent_access
    key = payload[:key] || payload
    key.with_indifferent_access.slice(:id, :remoteJid, :fromMe)
  end

  def find_message(source_id)
    channel.inbox.messages.find_by(source_id: source_id)
  end

  def soft_delete!(message)
    return if message.content_attributes&.dig('deleted')

    message.update!(
      content: I18n.t('conversations.messages.deleted'),
      content_type: :text,
      content_attributes: (message.content_attributes || {}).merge(
        'deleted' => true,
        'deleted_via_evolution_webhook' => true
      )
    )
  end
end
