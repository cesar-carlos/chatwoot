# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::MessageDeleteSyncService
  DELETED_VIA_KEY = 'deleted_via_evolution_go_webhook'

  pattr_initialize [:channel!, :data!]

  def perform
    return unless mark_inbound_deleted_enabled?

    key = extract_key
    return if key.blank? || key[:id].blank?
    return if from_me?(key)

    message = find_message(key[:id])
    if message.blank?
      Custom::Whatsapp::EvolutionGo::MutationStatsRecorder.record!(channel, 'inbound_delete_skipped')
      return
    end

    soft_delete!(message)
  end

  private

  def mark_inbound_deleted_enabled?
    ActiveModel::Type::Boolean.new.cast(
      (channel.provider_config || {})['mark_inbound_deleted']
    )
  end

  def extract_key
    Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor.normalize_key(
      (data.with_indifferent_access[:key] || data).with_indifferent_access
    )
  end

  def from_me?(key)
    ActiveModel::Type::Boolean.new.cast(key[:fromMe])
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
        DELETED_VIA_KEY => true
      )
    )
  end
end
