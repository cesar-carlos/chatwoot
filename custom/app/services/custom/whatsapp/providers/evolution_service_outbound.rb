# frozen_string_literal: true

module Custom::Whatsapp::Providers::EvolutionServiceOutbound
  private

  def apply_outbound_text(body, message)
    text = body.to_s
    text = Custom::Whatsapp::Evolution::MarkdownConverter.outbound(text) if convert_markdown_outbound?
    return text unless sign_msg?

    sender_name = message.sender&.available_name
    return text if sender_name.blank?

    delimiter = provider_config['sign_delimiter'].to_s.gsub('\\n', "\n").presence || "\n"
    ["*#{sender_name}:*", text].join(delimiter)
  end

  def build_quoted_context(phone_number, message)
    reply_id = message.content_attributes[:in_reply_to_external_id]
    return nil if reply_id.blank?

    {
      key: {
        id: reply_id,
        remoteJid: "#{normalize_phone(phone_number)}@s.whatsapp.net",
        fromMe: false
      },
      message: { conversation: reply_snippet(message, reply_id) }
    }
  end

  def reply_snippet(message, reply_id)
    original = message.conversation.messages.find_by(source_id: reply_id)
    original&.content&.truncate(100).to_s
  end

  def mark_incoming_read_after_reply(phone_number, message)
    return unless mark_read_on_reply?

    target = read_target_message(message)
    return if target.blank?

    api_client.mark_message_as_read(
      read_messages: [
        {
          id: target.source_id,
          fromMe: false,
          remoteJid: "#{normalize_phone(phone_number)}@s.whatsapp.net"
        }
      ]
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION] mark read on reply failed: #{e.message}"
  end

  def read_target_message(message)
    reply_id = message.content_attributes[:in_reply_to_external_id]
    scope = message.conversation.messages.incoming.where(inbox_id: message.inbox_id)
    return scope.find_by(source_id: reply_id) if reply_id.present?

    scope.where.not(source_id: [nil, '']).order(created_at: :desc).first
  end

  def create_send_error_private_note!(message, response)
    return unless notify_send_errors_private?
    return if message.blank? || message.conversation.blank?

    error_text = error_message(response).presence || 'Unknown error'
    message.conversation.messages.create!(
      account_id: message.account_id,
      inbox_id: message.inbox_id,
      message_type: :outgoing,
      private: true,
      sender: message.sender,
      content: "WhatsApp message could not be sent: #{error_text}"
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION] failed to create send error private note: #{e.message}"
  end

  def outbound_delay
    return nil unless send_random_delay?

    rand(500..2000)
  end

  def input_select_items(message)
    Array.wrap(message.content_attributes&.dig('items')).select do |item|
      item.is_a?(Hash) && item['title'].present?
    end
  end

  def sign_msg?
    ActiveModel::Type::Boolean.new.cast(provider_config['sign_msg'])
  end

  def send_random_delay?
    ActiveModel::Type::Boolean.new.cast(provider_config['send_random_delay'])
  end

  def send_templates_as_text?
    ActiveModel::Type::Boolean.new.cast(provider_config['send_templates_as_text'])
  end

  def convert_markdown_outbound?
    ActiveModel::Type::Boolean.new.cast(provider_config['convert_markdown_outbound'])
  end

  def mark_read_on_reply?
    ActiveModel::Type::Boolean.new.cast(provider_config['mark_read_on_reply'])
  end

  def notify_send_errors_private?
    ActiveModel::Type::Boolean.new.cast(provider_config['notify_send_errors_private'])
  end

  def provider_config
    whatsapp_channel.provider_config || {}
  end

  def api_client
    @api_client ||= Custom::Whatsapp::Evolution::ApiClient.new(
      base_url: provider_config['base_url'],
      api_key: provider_config['api_key'],
      instance_name: provider_config['instance_name']
    )
  end
end
