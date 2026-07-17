# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::DeleteSyncService
  pattr_initialize [:message!, { raise_errors: false }]

  def perform
    return false unless can_sync?

    dispatch_delete!
    true
  rescue StandardError => e
    revert_local_delete!
    Rails.logger.warn "[EVOLUTION_GO] delete sync failed for message #{message.id}: #{e.message}"
    raise if raise_errors

    false
  end

  private

  def can_sync?
    unless evolution_go_channel? && sync_delete_enabled? && message.source_id.present? && message.outgoing?
      return false
    end
    unless chat_jid.present?
      raise_or_skip!('Chat JID is required')
      return false
    end

    true
  end

  def raise_or_skip!(error_message)
    raise Custom::Whatsapp::EvolutionGo::ApiError, error_message if raise_errors
  end

  def dispatch_delete!
    response = api_client.delete_message(chat: chat_jid, message_id: message.source_id)
    return if response.success?

    Custom::Whatsapp::EvolutionGo::ApiClient.raise_unless_success!(
      response,
      'Failed to delete message on WhatsApp'
    )
  end

  # Keep CW and WA consistent: if API fails after local soft-delete, undo local flag.
  def revert_local_delete!
    attrs = (message.content_attributes || {}).stringify_keys
    return unless ActiveModel::Type::Boolean.new.cast(attrs['deleted'])

    attrs.delete('deleted')
    attrs.delete('deleted_at')
    attrs.delete(Custom::Whatsapp::EvolutionGo::MessageDeleteSyncService::DELETED_VIA_KEY)
    message.update_columns(content_attributes: attrs, updated_at: Time.current)
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION_GO] failed to revert local delete for message #{message.id}: #{e.message}"
  end

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
    @chat_jid ||= Custom::Whatsapp::EvolutionGo::ChatJid.for_message(message)
  end

  def api_client
    Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end
end
