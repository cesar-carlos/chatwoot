# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::DeleteSyncService
  pattr_initialize [:message!]

  def perform
    return unless evolution_go_channel?
    return unless sync_delete_enabled?
    return if message.source_id.blank?
    return unless message.outgoing?

    chat = chat_jid
    return if chat.blank?

    response = api_client.delete_message(chat: chat, message_id: message.source_id)
    return if response.success?

    Rails.logger.warn(
      "[EVOLUTION_GO] delete sync HTTP #{response.code} for message #{message.id}"
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION_GO] delete sync failed for message #{message.id}: #{e.message}"
  end

  private

  def evolution_go_channel?
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'
  end

  def channel
    @channel ||= message.inbox.channel
  end

  def sync_delete_enabled?
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['sync_delete_to_whatsapp'])
  end

  def chat_jid
    Custom::Whatsapp::EvolutionGo::ChatJid.for_message(message)
  end

  def api_client
    Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end
end
