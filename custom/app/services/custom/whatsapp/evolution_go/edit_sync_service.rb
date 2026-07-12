# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::EditSyncService
  pattr_initialize [:message!]

  def perform
    return unless can_sync?

    dispatch_edit!
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION_GO] edit sync failed for message #{message.id}: #{e.message}"
  end

  private

  def can_sync?
    evolution_go_channel? &&
      sync_edit_enabled? &&
      message.source_id.present? &&
      message.outgoing? &&
      chat_jid.present?
  end

  def dispatch_edit!
    response = api_client.edit_message(
      chat: chat_jid,
      message_id: message.source_id,
      message: whatsapp_edit_body
    )
    return if response.success?

    Rails.logger.warn(
      "[EVOLUTION_GO] edit sync HTTP #{response.code} for message #{message.id}"
    )
  end

  def evolution_go_channel?
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'
  end

  def channel
    @channel ||= message.inbox.channel
  end

  def sync_edit_enabled?
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['sync_edit_to_whatsapp'])
  end

  def chat_jid
    @chat_jid ||= Custom::Whatsapp::EvolutionGo::ChatJid.for_message(message)
  end

  def whatsapp_edit_body
    body = message.content.to_s
    prefix = Custom::Whatsapp::EvolutionGo::MessageEditSyncService::EDITED_PREFIX
    body = body.delete_prefix(prefix) if body.start_with?(prefix)
    apply_outbound_text(body)
  end

  def apply_outbound_text(body)
    text = body.to_s
    text = Custom::Whatsapp::Evolution::MarkdownConverter.outbound(text) if convert_markdown_outbound?
    return text unless sign_msg?

    sender_name = message.sender&.available_name
    return text if sender_name.blank?

    "#{sender_name}:#{sign_delimiter}#{text}"
  end

  def convert_markdown_outbound?
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['convert_markdown_outbound'])
  end

  def sign_msg?
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['sign_msg'])
  end

  def sign_delimiter
    (channel.provider_config || {})['sign_delimiter'].presence || "\n"
  end

  def api_client
    Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end
end
