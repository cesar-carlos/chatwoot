# frozen_string_literal: true

module Custom::Whatsapp::Providers::EvolutionGoServiceOutbound
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

    original = message.conversation.messages.find_by(source_id: reply_id)
    {
      messageId: reply_id,
      participant: quoted_participant(phone_number, original)
    }
  end

  def quoted_participant(phone_number, original)
    jid = original&.content_attributes&.dig('evolution_go_remote_jid').presence
    return jid if jid.present?

    delivery_jid(phone_number, original)
  end

  def delivery_jid(phone_number, _context_message = nil)
    value = phone_number.to_s.strip
    return value if value.include?('@')

    "#{normalize_phone(value)}@s.whatsapp.net"
  end

  def mark_incoming_read_after_reply(phone_number, message)
    return unless mark_read_on_reply?

    target = read_target_message(message)
    return if target.blank? || target.source_id.blank?

    api_client.mark_messages_read(number: phone_number, ids: [target.source_id])
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION_GO] mark read on reply failed: #{e.message}"
  end

  def read_target_message(message)
    replied = replied_to_incoming_message(message)
    return replied if replied.present?

    latest_unread_incoming_message(message)
  end

  def replied_to_incoming_message(message)
    reply_id = message.content_attributes[:in_reply_to_external_id]
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
    Rails.logger.warn "[EVOLUTION_GO] failed to create send error private note: #{e.message}"
  end

  def outbound_delay
    return nil unless send_random_delay?

    rand(500..2000)
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
        media_source: Custom::Whatsapp::Evolution::MediaPayload.for_attachment(attachment),
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
    mediatype = attachment_mediatype(attachment)
    api_client.send_media(
      number: phone_number,
      type: mediatype,
      url: media_source,
      caption: include_caption ? attachment_caption(message, mediatype) : nil,
      filename: attachment.file.filename.to_s,
      quoted: build_quoted_context(phone_number, message),
      delay: outbound_delay
    )
  end

  def attachment_caption(message, mediatype)
    caption = message.content.presence
    return caption unless caption.present? && mediatype != 'audio'

    apply_outbound_text(caption, message)
  end

  def attachment_mediatype(attachment)
    return 'sticker' if attachment.file_type == 'sticker'
    return attachment.file_type if %w[image audio video].include?(attachment.file_type)

    'document'
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
