# frozen_string_literal: true

# Hooks into message updates to sync deletions from Chatwoot back to WhatsApp
# when sync_delete_to_whatsapp is enabled for an Evolution inbox.
module Custom::Message::EvolutionDeleteSync
  private

  def sync_evolution_delete_to_whatsapp
    return unless evolution_message_marked_deleted?

    Custom::Whatsapp::Evolution::DeleteSyncService.new(message: self).perform
  end

  def evolution_message_marked_deleted?
    channel = evolution_whatsapp_channel
    return false unless channel
    return false unless evolution_sync_delete_enabled?(channel)
    return false unless newly_marked_deleted?

    true
  end

  def evolution_whatsapp_channel
    channel = conversation&.inbox&.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'

    channel
  end

  def evolution_sync_delete_enabled?(channel)
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['sync_delete_to_whatsapp'])
  end

  def newly_marked_deleted?
    return false if source_id.blank?
    return false unless ActiveModel::Type::Boolean.new.cast(content_attributes[:deleted])
    return false if ActiveModel::Type::Boolean.new.cast(content_attributes[:deleted_via_evolution_webhook])

    before = (content_attributes_before_last_save || {}).with_indifferent_access
    !ActiveModel::Type::Boolean.new.cast(before[:deleted])
  end
end
