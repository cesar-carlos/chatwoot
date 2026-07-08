# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::EditSyncService
  pattr_initialize [:message!]

  def perform
    return unless evolution_go_channel?
    return unless sync_edit_enabled?
    return if message.source_id.blank?
    return unless message.outgoing?

    response = api_client.edit_message(
      chat: chat_jid,
      message_id: message.source_id,
      message: whatsapp_edit_body
    )
    return if response.success?

    Rails.logger.warn(
      "[EVOLUTION_GO] edit sync HTTP #{response.code} for message #{message.id}"
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION_GO] edit sync failed for message #{message.id}: #{e.message}"
  end

  private

  def evolution_go_channel?
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'
  end

  def channel
    @channel ||= message.inbox.channel
  end

  def sync_edit_enabled?
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['sync_edit_to_whatsapp'])
  end

  def chat_jid
    attrs = message.content_attributes || {}
    jid = attrs['evolution_go_remote_jid'].presence || attrs[:evolution_go_remote_jid].presence
    return jid if jid.present?

    contact_jid = message.conversation.contact_inbox.source_id.to_s
    return contact_jid if contact_jid.include?('@')

    phone = contact_jid.gsub(/\D/, '')
    return if phone.blank?

    "#{phone}@s.whatsapp.net"
  end

  def whatsapp_edit_body
    body = message.content.to_s
    prefix = Custom::Whatsapp::EvolutionGo::MessageEditSyncService::EDITED_PREFIX
    body.start_with?(prefix) ? body.delete_prefix(prefix) : body
  end

  def api_client
    Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end
end
