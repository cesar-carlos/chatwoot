# frozen_string_literal: true

module Custom::Message::EvolutionGoEditSync
  private

  def sync_evolution_go_edit_to_whatsapp
    return unless evolution_go_content_changed_for_sync?

    Custom::Whatsapp::EvolutionGo::EditSyncService.new(message: self).perform
  end

  def evolution_go_content_changed_for_sync?
    channel = evolution_go_whatsapp_channel_for_edit
    return false unless channel
    return false unless evolution_go_sync_edit_enabled?(channel)
    return false if source_id.blank?
    return false unless outgoing?
    return false if private?
    return false unless saved_change_to_content?

    true
  end

  def evolution_go_whatsapp_channel_for_edit
    channel = conversation&.inbox&.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'

    channel
  end

  def evolution_go_sync_edit_enabled?(channel)
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['sync_edit_to_whatsapp'])
  end
end
