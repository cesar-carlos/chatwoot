# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::TranscriptionsController < Api::V1::Accounts::BaseController
  AUDIO_MAX_SIZE = 25.megabytes
  GROQ_API_URL = 'https://api.groq.com/openai/v1/audio/transcriptions'.freeze
  DEFAULT_MODEL = 'whisper-large-v3-turbo'.freeze
  REQUEST_TIMEOUT = 60
  OPEN_TIMEOUT = 10
  ALLOWED_AUDIO_TYPES = %w[
    audio/flac audio/mp3 audio/mp4 audio/m4a audio/mpeg audio/mpga
    audio/ogg audio/wav audio/x-wav audio/webm
  ].freeze

  before_action :check_feature_enabled
  before_action :validate_groq_token
  before_action :validate_audio_file, only: [:create]

  def create
    Rails.logger.info "Starting audio transcription: attachment_id=#{params[:attachment_id]} user_id=#{current_user.id}"

    check_cache_and_transcribe
  rescue StandardError => e
    Rails.logger.error "Audio transcription failed: #{e.message} attachment_id=#{params[:attachment_id]}"
    handle_error(e)
  end

  def presets
    render json: {
      presets: %w[voice high_quality small_size],
      default_preset: 'voice'
    }
  end

  private

  def check_cache_and_transcribe
    attachment = find_attachment
    cached_transcription = get_cached_transcription(attachment)

    if cached_transcription && !force_refresh?
      Rails.logger.info "Audio transcription cache hit: attachment_id=#{attachment&.id}"
      render json: format_cached_response(cached_transcription)
    else
      transcription = perform_transcription(attachment)
      save_to_cache(attachment, transcription) if attachment
      Rails.logger.info "Audio transcription completed: attachment_id=#{attachment&.id} length=#{transcription[:text]&.length}"
      render json: transcription.merge(cached: false)
    end
  end

  def find_attachment
    return nil if params[:attachment_id].blank?

    Current.account.attachments.find_by(id: params[:attachment_id])
  end

  def get_cached_transcription(attachment)
    return nil unless attachment
    return nil unless attachment.meta.is_a?(Hash)

    attachment.meta['transcription']
  end

  def force_refresh?
    params[:force_refresh].to_s == 'true'
  end

  def format_cached_response(cached_data)
    {
      text: cached_data['text'],
      state: cached_data['state'],
      provider: cached_data['provider'],
      model: cached_data['model'],
      metadata: cached_data['metadata'] || {},
      cached: true
    }
  end

  def perform_transcription(attachment)
    audio_file = if attachment
                   fetch_audio_from_attachment(attachment)
                 else
                   params[:file]
                 end

    groq_response = send_to_groq_api(audio_file)
    parse_groq_response(groq_response)
  ensure
    cleanup_temp_file(audio_file) if audio_file.is_a?(Hash)
  end

  def fetch_audio_from_attachment(attachment)
    blob = attachment.file.blob
    temp_dir = Rails.root.join('tmp/uploads/audio-transcriptions')
    FileUtils.mkdir_p(temp_dir)
    temp_file_name = "#{blob.key}-#{blob.filename}"

    if blob.filename.extension_without_delimiter.blank?
      extension = extension_from_content_type(blob.content_type)
      temp_file_name = "#{temp_file_name}.#{extension}" if extension.present?
    end

    temp_file_path = File.join(temp_dir, temp_file_name)

    File.open(temp_file_path, 'wb') do |file|
      blob.open { |blob_file| IO.copy_stream(blob_file, file) }
    end

    { tempfile: File.open(temp_file_path, 'rb'), filename: File.basename(temp_file_path), type: blob.content_type }
  end

  def send_to_groq_api(audio_file)
    conn = Faraday.new(url: GROQ_API_URL) do |f|
      f.request :multipart
      f.request :url_encoded
      f.adapter Faraday.default_adapter
      f.options.timeout = REQUEST_TIMEOUT
      f.options.open_timeout = OPEN_TIMEOUT
    end

    payload = build_groq_payload(audio_file)

    response = conn.post do |req|
      req.headers['Authorization'] = "Bearer #{current_user.groq_token}"
      req.body = payload
    end

    handle_groq_response(response)
  end

  def build_groq_payload(audio_file)
    file_io, filename, content_type = extract_file_params(audio_file)

    payload = {
      file: Faraday::UploadIO.new(file_io, content_type, filename),
      model: params[:model] || DEFAULT_MODEL,
      response_format: 'verbose_json',
      timestamp_granularities: %w[word segment]
    }

    payload[:language] = params[:language] if params[:language].present?
    payload[:prompt] = params[:prompt] if params[:prompt].present?

    payload
  end

  def extract_file_params(audio_file)
    if audio_file.is_a?(Hash)
      [audio_file[:tempfile], audio_file[:filename], audio_file[:type]]
    else
      [audio_file.tempfile, audio_file.original_filename, audio_file.content_type]
    end
  end

  def handle_groq_response(response)
    unless response.success?
      error_body = begin
        JSON.parse(response.body)
      rescue StandardError
        {}
      end
      error_message = error_body.dig('error', 'message') || response.body
      raise StandardError, error_message
    end

    response
  end

  def parse_groq_response(response)
    data = JSON.parse(response.body)

    {
      text: data['text'],
      state: 'success',
      provider: 'groq',
      model: data['model'] || DEFAULT_MODEL,
      metadata: {
        transcribed_at: Time.current.to_i,
        segments: data['segments'] || [],
        language: data['language'],
        duration: data['duration']
      }
    }
  end

  def save_to_cache(attachment, transcription_data)
    return unless attachment

    # FORK: safe merge of meta to preserve other keys
    current_meta = attachment.meta.to_h
    current_meta['transcription'] = transcription_data
    current_meta['transcribed_text'] = transcription_data[:text] # backward compatibility

    attachment.update!(meta: current_meta)
  end

  def cleanup_temp_file(audio_file_hash)
    return unless audio_file_hash[:tempfile]

    audio_file_hash[:tempfile].close
    FileUtils.rm_f(audio_file_hash[:tempfile].path)
  end

  def check_feature_enabled
    return if Current.account.audio_transcriptions

    render json: {
      error_type: 'feature_disabled',
      message: 'Audio transcription is not enabled for this account'
    }, status: :forbidden
  end

  def validate_groq_token
    return if current_user&.groq_token.present?

    render json: {
      error_type: 'token_missing',
      translation_key: 'AUDIO.TOKEN_MISSING.MESSAGE',
      message: 'Groq API token not configured in user profile'
    }, status: :unprocessable_entity
  end

  # rubocop:disable Metrics/MethodLength
  def validate_audio_file
    if params[:file].blank? && params[:attachment_id].blank?
      render json: {
        error_type: 'validation_error',
        message: 'Audio file or attachment_id is required'
      }, status: :unprocessable_entity
      return
    end

    return if params[:file].blank?

    file_size = params[:file].size
    if file_size > AUDIO_MAX_SIZE
      render json: {
        error_type: 'validation_error',
        translation_key: 'AUDIO.FILE_TOO_LARGE',
        message: "File size #{(file_size / 1.megabyte).round(1)}MB exceeds maximum of 25MB"
      }, status: :unprocessable_entity
      return
    end

    content_type = params[:file].content_type
    return if ALLOWED_AUDIO_TYPES.include?(content_type)

    render json: {
      error_type: 'validation_error',
      translation_key: 'AUDIO.API_ERROR.INVALID_FORMAT',
      message: "Audio format #{content_type} is not supported"
    }, status: :unprocessable_entity
  end
  # rubocop:enable Metrics/MethodLength

  def extension_from_content_type(content_type)
    subtype = content_type.to_s.downcase.split(';').first.to_s.split('/').last.to_s
    return if subtype.blank?

    {
      'x-m4a' => 'm4a',
      'x-wav' => 'wav',
      'x-mp3' => 'mp3'
    }.fetch(subtype, subtype)
  end

  def handle_error(error)
    error_data = format_error_message(error.message)

    render json: {
      error_type: 'transcription_error',
      translation_key: error_data[:key],
      message: error_data[:message]
    }, status: :unprocessable_entity
  end

  def format_error_message(error_msg)
    matched_error = error_patterns.find { |pattern, _| error_msg.match?(pattern) }
    matched_error ? matched_error[1] : default_error(error_msg)
  end

  def error_patterns
    {
      /api key|invalid_api_key|authentication/i => { message: 'Invalid or expired Groq API key', key: 'AUDIO.API_ERROR.INVALID_KEY' },
      /model not found/i => { message: 'Transcription model not found', key: 'AUDIO.API_ERROR.MODEL_NOT_FOUND' },
      /invalid audio format|unsupported/i => { message: 'Audio format not supported by API', key: 'AUDIO.API_ERROR.INVALID_FORMAT' },
      /file too large|size/i => { message: 'File too large for processing', key: 'AUDIO.API_ERROR.FILE_TOO_LARGE' },
      /timeout|timed out/i => { message: 'Processing timeout. Try a smaller file', key: 'AUDIO.API_ERROR.TIMEOUT' },
      /connection|network/i => { message: 'Connection problem with Groq API', key: 'AUDIO.API_ERROR.CONNECTION' },
      /unauthorized|forbidden|401|403/i => { message: 'Unauthorized. Check your Groq API token.', key: 'AUDIO.API_ERROR.UNAUTHORIZED' },
      /rate limit|429/i => { message: 'Rate limit exceeded. Please wait and try again.', key: 'AUDIO.API_ERROR.RATE_LIMIT' }
    }
  end

  def default_error(error_msg)
    { message: "Transcription failed: #{error_msg}", key: 'AUDIO.API_ERROR.GENERIC' }
  end
end
# rubocop:enable Metrics/ClassLength
