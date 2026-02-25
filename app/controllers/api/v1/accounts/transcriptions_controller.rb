# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::TranscriptionsController < Api::V1::Accounts::BaseController
  AUDIO_MAX_SIZE = 25.megabytes
  GROQ_API_URL = 'https://api.groq.com/openai/v1/audio/transcriptions'.freeze
  DEFAULT_MODEL = 'whisper-large-v3-turbo'.freeze
  REQUEST_TIMEOUT = 60
  OPEN_TIMEOUT = 10
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
      presets: AudioConverterService::QUALITY_PRESETS.keys.map(&:to_s),
      default_preset: 'voice'
    }
  end

  private

  def check_cache_and_transcribe
    attachment = find_attachment
    return if performed? # Early return if find_attachment already rendered error response

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

    # Attachment belongs_to :account, so we query directly with account_id for security
    attachment = Attachment.find_by(id: params[:attachment_id], account_id: Current.account.id)

    if params[:attachment_id].present? && attachment.nil?
      render json: {
        error_type: 'attachment_not_found',
        message: "Attachment with id #{params[:attachment_id]} not found or does not belong to this account"
      }, status: :not_found
      return nil
    end

    attachment
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
    source_audio_file = attachment ? fetch_audio_from_attachment(attachment) : params[:file]
    prepared_audio_file = prepare_audio_file(source_audio_file)

    groq_response = send_to_groq_api(prepared_audio_file)
    parse_groq_response(groq_response)
  ensure
    cleanup_temp_file(source_audio_file) if source_audio_file.is_a?(Hash)
    cleanup_temp_file(prepared_audio_file) if prepared_audio_file.is_a?(Hash) && prepared_audio_file != source_audio_file
  end

  def prepare_audio_file(audio_file)
    converter = AudioConverterService.new(audio_file, quality_preset)

    audio_type = audio_file.is_a?(Hash) ? audio_file[:type] : audio_file.content_type
    Rails.logger.info "Audio file before conversion check: type=#{audio_type} needs_conversion=#{converter.needs_conversion?}"

    return audio_file unless converter.needs_conversion?

    validate_ffmpeg_availability!
    converted = converter.convert
    Rails.logger.info "Audio converted: type=#{converted[:type]} filename=#{converted[:filename]}"
    converted
  end

  # rubocop:disable Metrics/AbcSize
  def fetch_audio_from_attachment(attachment)
    blob = attachment.file.blob
    temp_dir = Rails.root.join('tmp/uploads/audio-transcriptions')
    FileUtils.mkdir_p(temp_dir)

    original_filename = blob.filename.to_s
    content_type = blob.content_type

    # Normalize .oga extension to .ogg for Groq compatibility (validates by filename extension)
    if original_filename.downcase.end_with?('.oga')
      original_filename = original_filename.sub(/\.oga\z/i, '.ogg')
      content_type = 'audio/ogg' if %w[audio/opus audio/oga audio/x-oga].include?(content_type)
    end

    temp_file_name = "#{blob.key}-#{original_filename}"

    if blob.filename.extension_without_delimiter.blank?
      extension = extension_from_content_type(content_type)
      temp_file_name = "#{temp_file_name}.#{extension}" if extension.present?
    end

    temp_file_path = File.join(temp_dir, temp_file_name)

    File.open(temp_file_path, 'wb') do |file|
      blob.open { |blob_file| IO.copy_stream(blob_file, file) }
    end

    { tempfile: File.open(temp_file_path, 'rb'), filename: File.basename(temp_file_path), type: content_type }
  end
  # rubocop:enable Metrics/AbcSize

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

    Rails.logger.info "Building Groq payload: filename=#{filename} content_type=#{content_type}"

    # Build payload according to Groq API docs
    payload = {
      file: Faraday::UploadIO.new(file_io, content_type, filename),
      model: params[:model] || DEFAULT_MODEL,
      response_format: 'verbose_json',
      temperature: '0.0' # Must be string for multipart form-data
    }

    # Optional parameters
    payload[:language] = params[:language] if params[:language].present?
    payload[:prompt] = params[:prompt] if params[:prompt].present?

    payload
  end

  def extract_file_params(audio_file)
    if audio_file.is_a?(Hash)
      content_type = normalize_content_type_for_groq(audio_file[:type])
      filename = normalized_filename(audio_file[:filename], content_type)
      [audio_file[:tempfile], filename, content_type]
    else
      content_type = normalize_content_type_for_groq(audio_file.content_type)
      filename = normalized_filename(audio_file.original_filename, content_type)
      [audio_file.tempfile, filename, content_type]
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
      transcribed_at: Time.current.to_i,
      metadata: {
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
    }, status: :unprocessable_content
  end

  def validate_audio_file
    if params[:file].blank? && params[:attachment_id].blank?
      render json: {
        error_type: 'validation_error',
        message: 'Audio file or attachment_id is required'
      }, status: :unprocessable_content
      return
    end

    return if params[:file].blank?

    file_size = params[:file].size
    if file_size > AUDIO_MAX_SIZE
      render json: {
        error_type: 'validation_error',
        translation_key: 'AUDIO.FILE_TOO_LARGE',
        message: "File size #{(file_size / 1.megabyte).round(1)}MB exceeds maximum of 25MB"
      }, status: :unprocessable_content
      return
    end

    true
  end

  def validate_ffmpeg_availability!
    return if AudioConverterService.ffmpeg_installed?

    raise StandardError, 'FFmpeg is not installed. Unable to convert audio format.'
  end

  def quality_preset
    params[:quality_preset] || 'voice'
  end

  def extension_from_content_type(content_type)
    subtype = content_type.to_s.downcase.split(';').first.to_s.split('/').last.to_s
    return if subtype.blank?

    {
      'oga' => 'ogg',
      'x-oga' => 'ogg',
      'x-m4a' => 'm4a',
      'x-wav' => 'wav',
      'x-mp3' => 'mp3'
    }.fetch(subtype, subtype)
  end

  def normalize_content_type_for_groq(content_type)
    # Only normalize problematic MIME types that Groq doesn't recognize
    # audio/opus is valid and should NOT be remapped to audio/ogg
    return 'audio/ogg' if %w[audio/oga audio/x-oga].include?(content_type)

    content_type
  end

  def normalized_filename(filename, content_type)
    return filename unless content_type == 'audio/ogg'
    return filename unless filename.to_s.downcase.end_with?('.oga')

    filename.to_s.sub(/\.oga\z/i, '.ogg')
  end

  def handle_error(error)
    error_data = format_error_message(error.message)

    render json: {
      error_type: 'transcription_error',
      translation_key: error_data[:key],
      message: error_data[:message]
    }, status: error_data[:status]
  end

  def format_error_message(error_msg)
    matched_error = error_patterns.find { |pattern, _| error_msg.match?(pattern) }
    matched_error ? matched_error[1] : default_error(error_msg)
  end

  # rubocop:disable Metrics/MethodLength
  def error_patterns
    {
      /api key|invalid_api_key|authentication/i => {
        message: 'Invalid or expired Groq API key',
        key: 'AUDIO.API_ERROR.INVALID_KEY',
        status: :unauthorized
      },
      /model not found/i => {
        message: 'Transcription model not found',
        key: 'AUDIO.API_ERROR.MODEL_NOT_FOUND',
        status: :unprocessable_content
      },
      /invalid audio format|unsupported/i => {
        message: 'Audio format not supported by API',
        key: 'AUDIO.API_ERROR.INVALID_FORMAT',
        status: :unprocessable_content
      },
      /file too large|size/i => {
        message: 'File too large for processing',
        key: 'AUDIO.API_ERROR.FILE_TOO_LARGE',
        status: :unprocessable_content
      },
      /timeout|timed out/i => {
        message: 'Processing timeout. Try a smaller file',
        key: 'AUDIO.API_ERROR.TIMEOUT',
        status: :request_timeout
      },
      /connection|network/i => {
        message: 'Connection problem with Groq API',
        key: 'AUDIO.API_ERROR.CONNECTION',
        status: :bad_gateway
      },
      /unauthorized|forbidden|401|403/i => {
        message: 'Unauthorized. Check your Groq API token.',
        key: 'AUDIO.API_ERROR.UNAUTHORIZED',
        status: :unauthorized
      },
      /rate limit|429/i => {
        message: 'Rate limit exceeded. Please wait and try again.',
        key: 'AUDIO.API_ERROR.RATE_LIMIT',
        status: :too_many_requests
      },
      /ffmpeg/i => {
        message: 'FFmpeg not available. Audio format conversion failed.',
        key: 'AUDIO.API_ERROR.FFMPEG_MISSING',
        status: :service_unavailable
      }
    }
  end
  # rubocop:enable Metrics/MethodLength

  def default_error(error_msg)
    {
      message: "Transcription failed: #{error_msg}",
      key: 'AUDIO.API_ERROR.GENERIC',
      status: :unprocessable_content
    }
  end
end
# rubocop:enable Metrics/ClassLength
