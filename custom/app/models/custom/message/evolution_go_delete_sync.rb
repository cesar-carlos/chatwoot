# frozen_string_literal: true

# Syncs agent-initiated deletions from Chatwoot to WhatsApp via Evolution Go API.
module Custom::Message::EvolutionGoDeleteSync
  private

  def sync_evolution_go_delete_to_whatsapp
    return unless evolution_go_message_marked_deleted?

    Custom::Whatsapp::EvolutionGo::DeleteSyncService.new(message: self).perform
  end

  def evolution_go_message_marked_deleted?
    return false if instance_variable_get(:@evolution_go_delete_synced_inline)

    channel = evolution_go_whatsapp_channel
    return false unless channel
    return false unless evolution_go_sync_delete_enabled?(channel)
    return false unless outgoing?
    return false unless newly_marked_deleted_for_go_sync?

    true
  end

  def evolution_go_whatsapp_channel
    channel = conversation&.inbox&.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'

    channel
  end

  def evolution_go_sync_delete_enabled?(channel)
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['sync_delete_to_whatsapp'])
  end

  def newly_marked_deleted_for_go_sync?
    return false if source_id.blank?
    return false unless ActiveModel::Type::Boolean.new.cast(content_attributes[:deleted])
    return false if deleted_via_webhook?

    before = (content_attributes_before_last_save || {}).with_indifferent_access
    !ActiveModel::Type::Boolean.new.cast(before[:deleted])
  end

  def deleted_via_webhook?
    attrs = content_attributes.with_indifferent_access
    ActiveModel::Type::Boolean.new.cast(attrs[:deleted_via_evolution_go_webhook]) ||
      ActiveModel::Type::Boolean.new.cast(attrs[:deleted_via_evolution_webhook])
  end
end
