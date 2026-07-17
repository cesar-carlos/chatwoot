# frozen_string_literal: true

# rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize, Metrics/MethodLength
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
      # Agent/phone edits without a known CW message must not invent an incoming row.
      if from_me?(key)
        Custom::Whatsapp::EvolutionGo::MutationStatsRecorder.record!(channel, 'inbound_edit_skipped')
        return
      end

      created = create_edited_message(key, body, original)
      Custom::Whatsapp::EvolutionGo::MutationStatsRecorder.record!(channel, 'inbound_edit_skipped') unless created
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

  def from_me?(key)
    ActiveModel::Type::Boolean.new.cast(key[:fromMe])
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

  def create_edited_message(key, body, original)
    remote_jid = key[:remoteJid].presence || original&.content_attributes&.dig('evolution_go_remote_jid')
    wa_id = jid_resolver.phone_from_jid(remote_jid)
    return false if wa_id.blank?

    formatted_body = apply_inbound_formatting(body)
    envelope = {
      event: 'MESSAGE',
      instance: channel.provider_config['instance_name'],
      data: {
        key: {
          id: "#{key[:id]}-edited",
          fromMe: false,
          remoteJid: remote_jid
        }.compact,
        pushName: original&.sender&.name,
        message: { conversation: formatted_body },
        messageTimestamp: Time.current.to_i
      }
    }

    normalized = Custom::Whatsapp::Webhooks::EvolutionGoNormalizer.new(channel, envelope).perform
    return false if normalized.blank?

    Custom::Whatsapp::EvolutionGo::InboundMessageProcessor.process(
      channel,
      normalized.merge(phone_number: channel.phone_number)
    )
    mark_created_message_edited!("#{key[:id]}-edited")
    true
  end

  def mark_created_message_edited!(source_id)
    created = channel.inbox.messages.find_by(source_id: source_id)
    return if created.blank?

    attrs = (created.content_attributes || {}).stringify_keys
    attrs['edited'] = true
    attrs['edited_at'] = Time.current.utc.iso8601(3)
    attrs['edited_via_evolution_go_webhook'] = true
    created.update!(content_attributes: attrs)
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

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::EvolutionGo::JidResolver.new(channel.provider_config || {})
  end
end
# rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize, Metrics/MethodLength
