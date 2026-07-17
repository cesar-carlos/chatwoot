# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::MessageContentEditService
  EDITED_PREFIX = Custom::Whatsapp::EvolutionGo::MessageEditSyncService::EDITED_PREFIX
  MAX_LENGTH = 4096

  pattr_initialize [:message!, :content!]

  def perform
    validate!
    return message if noop?

    # WA first (like ReactSyncService) so the agent sees API failures.
    sync_to_whatsapp!
    apply_edit!
    message
  end

  private

  def validate!
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Not an Evolution Go channel' unless evolution_go_channel?
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Message edit sync is disabled' unless sync_edit_enabled?
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Only outgoing messages can be edited' unless message.outgoing?
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Private notes cannot be edited on WhatsApp' if message.private?
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Message source_id is required' if message.source_id.blank?
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Deleted messages cannot be edited' if deleted?
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Message content is required' if new_content.blank?
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Message content is too long' if new_content.length > MAX_LENGTH
  end

  def sync_to_whatsapp!
    synced = Custom::Whatsapp::EvolutionGo::EditSyncService.new(
      message: message,
      content: new_content,
      raise_errors: true
    ).perform
    return if synced

    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Failed to edit message on WhatsApp'
  end

  def apply_edit!
    attrs = (message.content_attributes || {}).stringify_keys
    attrs['edited'] = true
    attrs['edited_at'] = Time.current.utc.iso8601(3)
    # Already synced inline — skip after_update_commit re-dispatch.
    attrs['edited_via_evolution_go_webhook'] = false

    message.instance_variable_set(:@evolution_go_edit_synced_inline, true)
    message.update!(
      content: new_content,
      content_attributes: attrs
    )
  end

  def noop?
    bare_current == new_content
  end

  def new_content
    @new_content ||= content.to_s.strip
  end

  def bare_current
    message.content.to_s.delete_prefix(EDITED_PREFIX).strip
  end

  def deleted?
    ActiveModel::Type::Boolean.new.cast((message.content_attributes || {})['deleted'])
  end

  def evolution_go_channel?
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'
  end

  def sync_edit_enabled?
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['sync_edit_to_whatsapp'])
  end

  def channel
    @channel ||= message.inbox.channel
  end
end
