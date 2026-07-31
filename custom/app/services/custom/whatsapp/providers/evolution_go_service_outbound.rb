# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength, Metrics/MethodLength, Metrics/ParameterLists
module Custom::Whatsapp::Providers::EvolutionGoServiceOutbound
  INTERACTIVE_LIST_BUTTON_TEXT = 'Options'
  INTERACTIVE_FOOTER_TEXT = 'Chatwoot'

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
    reply_id = message.content_attributes.with_indifferent_access[:in_reply_to_external_id]
    return nil if reply_id.blank?

    original = message.conversation.messages.find_by(source_id: reply_id)
    {
      messageId: reply_id,
      participant: quoted_participant(phone_number, original)
    }.compact
  end

  def quoted_participant(phone_number, original)
    # Outgoing quotes need the business JID. Do not use evolution_go_remote_jid here —
    # on fromMe messages that field stores the chat peer, not the sender.
    if original.present? && !original.incoming?
      return business_participant_jid
    end

    jid = original&.content_attributes&.dig('evolution_go_remote_jid').presence
    return jid if jid.present?

    delivery_jid(phone_number, original)
  end

  def business_participant_jid
    phone = channel_business_phone
    return if phone.blank?

    "#{phone}@s.whatsapp.net"
  end

  # Evolution Go inboxes often keep a placeholder channel phone (+55000…); the real
  # WhatsApp number is embedded in instance_name (e.g. FORTEZA-…-66996950396-…).
  def channel_business_phone
    phone = whatsapp_channel.phone_number.to_s.gsub(/\D/, '')
    return phone if phone.present? && !phone.start_with?('55000')

    phone_from_instance_name
  end

  def phone_from_instance_name
    name = (whatsapp_channel.provider_config || {})['instance_name'].to_s
    digits = name.scan(/\d{10,13}/).max_by(&:length)
    return if digits.blank?
    return digits if digits.start_with?('55') && digits.length >= 12
    return "55#{digits}" if digits.length.between?(10, 11)

    digits
  end

  # Prefer WhatsApp's real chat JID (@lid / WITHOUT-9 PN) over contact_inbox.source_id
  # (BR WITH-9 after merge_brazil_contacts) — same priority as react/delete/edit.
  def outbound_destination(phone_number, message)
    Custom::Whatsapp::EvolutionGo::ChatJid.for_message(message).presence || phone_number
  end

  def delivery_jid(phone_number, context_message = nil)
    stored = context_message&.content_attributes&.dig('evolution_go_remote_jid').presence
    return stored if stored.present?

    value = phone_number.to_s.strip
    return value if value.include?('@')

    "#{normalize_phone(value)}@s.whatsapp.net"
  end

  def delivery_options(phone_number, message)
    opts = {}
    opts[:format_jid] = true if lid_delivery?(phone_number, message)
    opts
  end

  def lid_delivery?(phone_number, message)
    return true if phone_number.to_s.end_with?('@lid')

    resolved = Custom::Whatsapp::EvolutionGo::ChatJid.for_message(message).to_s
    return true if resolved.end_with?('@lid')

    jid = message&.content_attributes&.dig('evolution_go_remote_jid').to_s
    jid.end_with?('@lid')
  end

  def mark_incoming_read_after_reply(phone_number, message)
    return unless mark_read_on_reply?

    target = read_target_message(message)
    return if target.blank? || target.source_id.blank?

    Custom::Whatsapp::EvolutionGo::MarkReadJob.perform_later(
      whatsapp_channel.id, phone_number, [target.source_id]
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION_GO] mark read on reply failed: #{e.message}"
  end

  def read_target_message(message)
    replied = replied_to_incoming_message(message)
    return replied if replied.present?

    latest_unread_incoming_message(message)
  end

  def replied_to_incoming_message(message)
    reply_id = message.content_attributes.with_indifferent_access[:in_reply_to_external_id]
    return nil if reply_id.blank?

    message.conversation.messages.incoming.find_by(source_id: reply_id)
  end

  def latest_unread_incoming_message(message)
    scope = message.conversation.messages
                   .incoming
                   .where(inbox_id: message.inbox_id)
                   .where.not(source_id: [nil, ''])
                   .order(created_at: :desc)

    scope.where.not(status: Message.statuses[:read]).first || scope.first
  end

  def create_send_error_private_note!(message, response_or_text)
    return unless notify_send_errors_private?
    return if message.blank? || message.conversation.blank?

    error_text = if response_or_text.is_a?(String)
                   response_or_text
                 else
                   error_message(response_or_text).presence || 'Unknown error'
                 end
    message.conversation.messages.create!(
      account_id: message.account_id,
      inbox_id: message.inbox_id,
      message_type: :outgoing,
      private: true,
      sender: message.sender,
      content: "WhatsApp message could not be sent: #{error_text}"
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION_GO] failed to create send error private note: #{e.message}"
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

  def dispatch_input_select(phone_number, title, items, quoted, delay, message)
    options = delivery_options(phone_number, message).merge(quoted: quoted, delay: delay)
    if items.size <= 3
      api_client.send_buttons(
        number: phone_number,
        title: title,
        description: title,
        footer: INTERACTIVE_FOOTER_TEXT,
        buttons: build_reply_buttons(items),
        **options
      )
    else
      api_client.send_list(
        number: phone_number,
        title: title,
        description: title,
        footer_text: INTERACTIVE_FOOTER_TEXT,
        button_text: INTERACTIVE_LIST_BUTTON_TEXT,
        sections: [build_list_section(items)],
        **options
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

  def send_attachment_message(phone_number, message)
    message_id = deliver_attachment_batch(phone_number, message)
    mark_incoming_read_after_reply(phone_number, message) if message_id.present?
    message_id
  end

  def deliver_attachment_batch(phone_number, message)
    message_id = nil

    message.attachments.each_with_index do |attachment, index|
      response = dispatch_attachment(
        phone_number: phone_number,
        attachment: attachment,
        media_source: sanitize_media_source(Custom::Whatsapp::Evolution::MediaPayload.for_attachment(attachment)),
        message: message,
        include_caption: index.zero?
      )
      message_id = process_attachment_response(response, message, index, message_id)
      return message_id if message_id == :failed
    end

    message_id == :failed ? nil : message_id
  end

  def process_attachment_response(response, message, index, message_id)
    if index.zero?
      first_id = process_response(response, message)
      return :failed if first_id.blank?

      return first_id
    end

    return message_id if response.success?

    Rails.logger.warn(
      "[EVOLUTION_GO] secondary attachment send failed for message #{message.id}: HTTP #{response.code}"
    )
    notify_partial_attachment_failure!(message, index + 1)
    message_id
  end

  def notify_partial_attachment_failure!(message, attachment_index)
    return unless notify_send_errors_private?
    return if message.blank? || message.conversation.blank?

    message.conversation.messages.create!(
      account_id: message.account_id,
      inbox_id: message.inbox_id,
      message_type: :outgoing,
      private: true,
      sender: message.sender,
      content: "Attachment ##{attachment_index} could not be sent to WhatsApp."
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION_GO] failed to create partial attachment private note: #{e.message}"
  end

  def dispatch_attachment(phone_number:, attachment:, media_source:, message:, include_caption: true)
    quoted = build_quoted_context(phone_number, message)
    delay = outbound_delay
    options = delivery_options(phone_number, message).merge(quoted: quoted, delay: delay)

    if attachment.contact?
      return api_client.send_contact(
        number: phone_number,
        vcard: build_evolution_go_vcard(attachment),
        **options
      )
    end

    if sticker_attachment?(attachment)
      return api_client.send_sticker(
        number: phone_number,
        sticker: media_source,
        **options
      )
    end

    mediatype = attachment_mediatype(attachment)
    api_client.send_media(
      number: phone_number,
      type: mediatype,
      url: media_source,
      caption: include_caption ? attachment_caption(message, mediatype) : nil,
      filename: attachment.file.filename.to_s,
      **options
    )
  end

  def contact_attachment?(message)
    message.attachments.one? && message.attachments.first.contact?
  end

  def send_contact_card_message(phone_number, message)
    attachment = message.attachments.first
    response = api_client.send_contact(
      number: phone_number,
      vcard: build_evolution_go_vcard(attachment),
      quoted: build_quoted_context(phone_number, message),
      delay: outbound_delay,
      **delivery_options(phone_number, message)
    )
    message_id = process_response(response, message)
    mark_incoming_read_after_reply(phone_number, message) if message_id.present?
    message_id
  end

  def build_evolution_go_vcard(attachment)
    entry = Whatsapp::ContactMessagePayloadBuilder.build(attachment)
    phone_digits = attachment.fallback_title.to_s.gsub(/\D/, '')
    full_name = entry.dig(:name, :formatted_name).presence || phone_digits

    {
      fullName: full_name,
      phone: phone_digits,
      organization: entry.dig(:org, :company)
    }.compact
  end

  def sticker_attachment?(attachment)
    attachment.file_type == 'sticker' ||
      (attachment.file_type == 'image' && attachment.file.content_type.to_s == 'image/webp')
  end

  def attachment_caption(message, mediatype)
    caption = message.content.presence
    return caption unless caption.present? && mediatype != 'audio'

    apply_outbound_text(caption, message)
  end

  def attachment_mediatype(attachment)
    return 'sticker' if sticker_attachment?(attachment)
    return attachment.file_type if %w[image audio video].include?(attachment.file_type)

    'document'
  end

  def sanitize_media_source(url)
    value = url.to_s
    return value unless value.start_with?('data:')

    value.sub(/\Adata:[^;]+;base64,/, '')
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

  def normalize_phone(phone)
    phone.to_s.gsub(/\D/, '')
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/MethodLength, Metrics/ParameterLists
