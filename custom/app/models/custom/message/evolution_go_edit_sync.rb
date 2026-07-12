# frozen_string_literal: true

module Custom::Message::EvolutionGoEditSync
  private

  def sync_evolution_go_edit_to_whatsapp
    return unless evolution_go_content_changed_for_sync?

    Custom::Whatsapp::EvolutionGo::EditSyncService.new(message: self).perform
  end

  def evolution_go_content_changed_for_sync?
    return false unless evolution_go_edit_sync_eligible?

    !evolution_go_edit_originated_from_webhook?
  end

  def evolution_go_edit_sync_eligible?
    channel = evolution_go_whatsapp_channel_for_edit
    channel.present? &&
      evolution_go_sync_edit_enabled?(channel) &&
      source_id.present? &&
      outgoing? &&
      !private? &&
      saved_change_to_content?
  end

  def evolution_go_whatsapp_channel_for_edit
    channel = conversation&.inbox&.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'

    channel
  end

  def evolution_go_sync_edit_enabled?(channel)
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['sync_edit_to_whatsapp'])
  end

  # Avoid CW → WA → webhook → CW content rewrite → WA loop.
  def evolution_go_edit_originated_from_webhook?
    attrs = (content_attributes || {}).with_indifferent_access
    return false unless ActiveModel::Type::Boolean.new.cast(attrs[:edited_via_evolution_go_webhook])

    before = (content_attributes_before_last_save || {}).with_indifferent_access
    !ActiveModel::Type::Boolean.new.cast(before[:edited_via_evolution_go_webhook])
  end
end
