# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::MessageEditSyncService
  EDITED_PREFIX = "Edited message:\n\n"

  pattr_initialize [:channel!, :data!]

  def perform
    return unless mark_inbound_edited_enabled?

    payload = data.with_indifferent_access
    key = (payload[:key] || {}).with_indifferent_access
    body = payload[:edited_body].presence || extract_edited_body(payload)
    return if key[:id].blank? || body.blank?

    original = channel.inbox.messages.find_by(source_id: key[:id])
    if original.blank?
      # Do not invent rows for unknown source_ids (edit-before-original / missing history).
      Custom::Whatsapp::EvolutionGo::MutationStatsRecorder.record!(channel, 'inbound_edit_skipped')
      return
    end

    update_original!(original, body)
  end

  private

  def mark_inbound_edited_enabled?
    ActiveModel::Type::Boolean.new.cast(
      (channel.provider_config || {})['mark_inbound_edited']
    )
  end

  def extract_edited_body(payload)
    Custom::Whatsapp::EvolutionGo::MessageEditPayloadExtractor.extract_edited_body(payload)
  end

  def update_original!(message, body)
    formatted_body = apply_inbound_formatting(body)
    bare_current = message.content.to_s.delete_prefix(EDITED_PREFIX).strip
    return if bare_current == formatted_body

    attrs = (message.content_attributes || {}).stringify_keys
    attrs['edited'] = true
    attrs['edited_at'] = Time.current.utc.iso8601(3)
    attrs['edited_via_evolution_go_webhook'] = true
    # Store bare text; UI shows the "Edited" badge via content_attributes.edited.
    # EDITED_PREFIX is still stripped for legacy rows that used the old format.
    message.update!(
      content: formatted_body,
      content_attributes: attrs
    )
  end

  def apply_inbound_formatting(body)
    return body unless convert_markdown_inbound?

    Custom::Whatsapp::Evolution::MarkdownConverter.inbound(body)
  end

  def convert_markdown_inbound?
    ActiveModel::Type::Boolean.new.cast(
      (channel.provider_config || {})['convert_markdown_inbound']
    )
  end
end
