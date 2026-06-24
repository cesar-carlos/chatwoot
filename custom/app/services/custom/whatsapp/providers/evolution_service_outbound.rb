# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength -- outbound transforms share provider_config/api_client context
module Custom::Whatsapp::Providers::EvolutionServiceOutbound
  INTERACTIVE_LIST_BUTTON_TEXT = 'Options'

  private

  def apply_outbound_text(body, message)
    text = body.to_s
    text = Custom::Whatsapp::Evolution::MarkdownConverter.outbound(text) if convert_markdown_outbound?
    return text unless sign_msg?

    sender_name = message.sender&.available_name
    return text if sender_name.blank?

    "#{sender_name}:#{sign_delimiter}#{text}"
  end

  def build_quoted_context(phone_number, message)
    reply_id = message.content_attributes[:in_reply_to_external_id]
    return nil if reply_id.blank?

    original = message.inbox.messages.find_by(source_id: reply_id)
    {
      key: {
        id: reply_id,
        remoteJid: quoted_remote_jid(phone_number, original),
        fromMe: quoted_from_me?(original)
      },
      message: { conversation: reply_snippet(original, reply_id) }
    }
  end

  def quoted_from_me?(original)
    return false if original.blank?

    !original.incoming?
  end

  def quoted_remote_jid(phone_number, original)
    jid = original&.content_attributes&.dig('evolution_remote_jid').presence
    return jid if jid.present?

    delivery_remote_jid(phone_number, original)
  end

  def reply_snippet(original, _reply_id)
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
          remoteJid: read_target_remote_jid(phone_number, target)
        }
      ]
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION] mark read on reply failed: #{e.message}"
  end

  def read_target_message(message)
    scope = message.conversation.messages
                   .incoming
                   .where(inbox_id: message.inbox_id)
                   .where.not(source_id: [nil, ''])
                   .order(created_at: :desc)

    scope.where.not(status: Message.statuses[:read]).first || scope.first
  end

  def read_target_remote_jid(phone_number, target)
    jid = target&.content_attributes&.dig('evolution_remote_jid').presence
    return jid if jid.present?

    delivery_remote_jid(phone_number, target)
  end

  def delivery_remote_jid(phone_number, context_message = nil)
    contact = context_message&.conversation&.contact
    stored = contact&.additional_attributes&.dig(
      Custom::Whatsapp::Evolution::ContactEnrichmentService::EVOLUTION_REMOTE_JID_KEY
    )
    return stored if stored.present?

    value = phone_number.to_s.strip
    return value if value.include?('@')

    digits = normalize_phone(value)
    "#{digits}@s.whatsapp.net"
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

  def dispatch_input_select(phone_number, title, items, quoted, delay)
    if items.size <= 3
      api_client.send_buttons(
        number: phone_number,
        title: title,
        buttons: build_reply_buttons(items),
        quoted: quoted,
        delay: delay
      )
    else
      api_client.send_list(
        number: phone_number,
        title: title,
        button_text: INTERACTIVE_LIST_BUTTON_TEXT,
        sections: [build_list_section(items)],
        quoted: quoted,
        delay: delay
      )
    end
  end

  def build_reply_buttons(items)
    items.map.with_index(1) do |item, index|
      {
        type: 'reply',
        displayText: item['title'].to_s.truncate(20),
        id: (item['value'].presence || index).to_s
      }
    end
  end

  def build_list_section(items)
    {
      title: 'Options',
      rows: items.map.with_index(1) do |item, index|
        {
          title: item['title'].to_s.truncate(24),
          description: item['description'].to_s.truncate(72),
          rowId: (item['value'].presence || index).to_s
        }
      end
    }
  end

  def sign_msg?
    ActiveModel::Type::Boolean.new.cast(provider_config['sign_msg'])
  end

  def sign_delimiter
    provider_config['sign_delimiter'].presence || "\n"
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
    @api_client ||= Custom::Whatsapp::Evolution::ApiClient.for_channel(whatsapp_channel)
  end

  # FORK: share contact card
  def contact_attachment?(message)
    message.attachments.one? && message.attachments.first.contact?
  end

  def send_contact_card_message(phone_number, message)
    attachment = message.attachments.first
    response = api_client.send_contact(
      number: phone_number,
      contact: [build_evolution_contact_payload(attachment)],
      quoted: build_quoted_context(phone_number, message),
      delay: outbound_delay
    )
    message_id = process_response(response, message)
    mark_incoming_read_after_reply(phone_number, message) if message_id.present?
    message_id
  end

  def build_evolution_contact_payload(attachment)
    entry = Whatsapp::ContactMessagePayloadBuilder.build(attachment)
    phone_digits = attachment.fallback_title.to_s.gsub(/\D/, '')
    full_name = entry.dig(:name, :formatted_name).presence || phone_digits

    payload = {
      fullName: full_name,
      wuid: phone_digits,
      phoneNumber: phone_digits
    }
    company = entry.dig(:org, :company)
    payload[:organization] = company if company.present?
    payload
  end
end
# rubocop:enable Metrics/ModuleLength
