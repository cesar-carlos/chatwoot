# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::MediaAttachmentService
  MIME_EXTENSION_PATTERNS = [
    [%r{image/png}, '.png'],
    [%r{image/}, '.jpg'],
    [%r{video/}, '.mp4'],
    [%r{audio/}, '.ogg']
  ].freeze

  pattr_initialize [:channel!, :message!, :attachment_payload!, :message_type!]

  def perform
    evolution_go_message = attachment_payload[:_evolution_go_message]
    return if evolution_go_message.blank?

    attach_from_go_message!(evolution_go_message)
  rescue ArgumentError => e
    Rails.logger.warn("[EVOLUTION_GO] media download rejected: #{e.message}")
    mark_media_failed!(e.message)
  rescue StandardError => e
    Rails.logger.error("[EVOLUTION_GO] media download failed: #{e.message}")
    raise
  end

  private

  def attach_from_go_message!(evolution_go_message)
    response = api_client.download_media(evolution_go_message)
    unless response.success?
      raise Custom::Whatsapp::EvolutionGo::ApiError.new(
        'Failed to download Evolution Go media',
        status: response.code,
        body: response.parsed_response
      )
    end

    tempfile = build_tempfile(response.parsed_response)
    return if tempfile.blank?

    create_attachment!(tempfile)
  end

  def create_attachment!(tempfile)
    message.attachments.create!(
      account_id: message.account_id,
      file_type: file_type,
      file: {
        io: tempfile,
        filename: tempfile.original_filename,
        content_type: tempfile.content_type
      }
    )
  end

  def mark_media_failed!(error_message)
    attrs = message.content_attributes.stringify_keys.merge(
      'evolution_go_media_failed' => true,
      'evolution_go_media_error' => error_message
    )
    message.update!(content_attributes: attrs)
  end

  def api_client
    Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end

  def file_type
    type = message_type.to_s
    return :image if %w[image sticker].include?(type)
    return :audio if %w[audio voice].include?(type)
    return :video if type == 'video'

    :file
  end

  def build_tempfile(parsed)
    base64 = extract_base64(parsed)
    return nil if base64.blank?

    extension = extension_for_media(parsed)
    tempfile = Tempfile.new(['evolution-go-media', extension])
    tempfile.binmode
    tempfile.write(Custom::Whatsapp::Evolution::MediaDecoder.decode!(base64))
    tempfile.rewind

    filename = parsed['fileName'] || attachment_payload[:filename] || "media#{extension}"
    content_type = parsed['mimetype'] || attachment_payload[:mimetype] || 'application/octet-stream'

    tempfile.define_singleton_method(:original_filename) { filename }
    tempfile.define_singleton_method(:content_type) { content_type }
    tempfile
  end

  def extract_base64(parsed)
    return parsed['base64'] if parsed.is_a?(Hash) && parsed['base64'].present?

    data = parsed['data'] if parsed.is_a?(Hash)
    return data['base64'] if data.is_a?(Hash) && data['base64'].present?

    nil
  end

  def extension_for_media(parsed)
    filename = parsed['fileName'] || attachment_payload[:filename]
    ext = File.extname(filename.to_s)
    return ext if ext.present?

    mimetype = (parsed['mimetype'] || attachment_payload[:mimetype]).to_s
    MIME_EXTENSION_PATTERNS.find { |pattern, _| mimetype.match?(pattern) }&.last || '.bin'
  end
end
