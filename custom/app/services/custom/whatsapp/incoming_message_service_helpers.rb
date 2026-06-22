# frozen_string_literal: true

module Custom::Whatsapp::IncomingMessageServiceHelpers
  def conversation_params
    params = super
    return params unless evolution_conversation_pending?

    params.merge(
      status: :pending,
      additional_attributes: pending_cycle_attributes(params[:additional_attributes])
    )
  end

  def pending_cycle_attributes(existing_attrs)
    (existing_attrs || {}).stringify_keys.merge(
      'evolution_pending_since' => Time.current.utc.iso8601(3)
    )
  end

  def download_attachment_file(attachment_payload)
    return download_evolution_media(attachment_payload) if evolution_channel? && attachment_payload[:_evolution_message].present?

    super
  end

  private

  def find_message_by_source_id(source_id)
    return super unless evolution_channel?

    return unless source_id

    @message = inbox.messages.find_by(source_id: source_id)
  end

  def evolution_channel?
    inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'evolution'
  end

  def evolution_conversation_pending?
    evolution_channel? && ActiveModel::Type::Boolean.new.cast(
      (inbox.channel.provider_config || {})['conversation_pending']
    )
  end

  def evolution_api_client
    Custom::Whatsapp::Evolution::ApiClient.for_channel(inbox.channel)
  end

  def message_content_attributes(message)
    attrs = super
    return attrs unless evolution_channel?

    remote_jid = message[:evolution_remote_jid].presence || message['evolution_remote_jid'].presence
    attrs[:evolution_remote_jid] = remote_jid if remote_jid.present?
    attrs
  end

  def download_evolution_media(attachment_payload)
    response = evolution_api_client.get_base64_from_media_message(
      message: attachment_payload[:_evolution_message]
    )
    return nil unless response.success?

    build_evolution_media_tempfile(response.parsed_response, attachment_payload)
  rescue ArgumentError => e
    Rails.logger.warn("[EVOLUTION] media download rejected: #{e.message}")
    nil
  rescue StandardError => e
    Rails.logger.error("[EVOLUTION] media download failed: #{e.message}")
    nil
  end

  def build_evolution_media_tempfile(parsed, attachment_payload)
    base64 = parsed['base64']
    return nil if base64.blank?

    extension = extension_for_media(parsed, attachment_payload)
    tempfile = Tempfile.new(['evolution-media', extension])
    tempfile.binmode
    tempfile.write(Custom::Whatsapp::Evolution::MediaDecoder.decode!(base64))
    tempfile.rewind

    filename = parsed['fileName'] || attachment_payload[:filename] || "media#{extension}"
    content_type = parsed['mimetype'] || attachment_payload[:mimetype] || 'application/octet-stream'

    tempfile.define_singleton_method(:original_filename) { filename }
    tempfile.define_singleton_method(:content_type) { content_type }
    tempfile
  end

  MIME_EXTENSION_PATTERNS = [
    [%r{image/png}, '.png'],
    [%r{image/}, '.jpg'],
    [%r{video/}, '.mp4'],
    [%r{audio/}, '.ogg']
  ].freeze

  def extension_for_media(parsed, attachment_payload)
    filename = parsed['fileName'] || attachment_payload[:filename]
    ext = File.extname(filename.to_s)
    return ext if ext.present?

    mimetype = (parsed['mimetype'] || attachment_payload[:mimetype]).to_s
    MIME_EXTENSION_PATTERNS.find { |pattern, _| mimetype.match?(pattern) }&.last || '.bin'
  end
end

Whatsapp::IncomingMessageServiceHelpers.prepend_mod_with('Whatsapp::IncomingMessageServiceHelpers')
