class Api::V1::Accounts::TranscriptionsController < Api::V1::Accounts::BaseController
  AUDIO_MAX_SIZE = 25.megabytes

  before_action :validate_groq_token
  before_action :validate_rate_limit, only: [:create]
  before_action :validate_audio_file, only: [:create]

  def create
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    log_lifecycle(:start, attachment_id: params[:attachment_id], provider: 'groq')

    result = orchestrator.perform
    duration_ms = elapsed_ms(started_at)
    log_lifecycle(:success, attachment_id: params[:attachment_id], provider: 'groq', duration_ms: duration_ms) if result.status == :ok

    render json: result.body, status: result.status
  rescue StandardError => e
    log_lifecycle(:error, attachment_id: params[:attachment_id], provider: 'groq', error: e.message)
    handle_error(e)
  end

  def presets
    render json: {
      presets: Custom::AudioConverterService::QUALITY_PRESETS.keys.map(&:to_s),
      default_preset: 'voice'
    }
  end

  private

  def orchestrator
    Custom::Transcription::Orchestrator.new(
      user_context: pundit_user,
      account: Current.account,
      params: params
    )
  end

  def validate_rate_limit
    return if Custom::Transcription::RateLimiter.new(user_id: current_user.id).within_limit?

    render json: {
      error_type: 'rate_limit_exceeded',
      translation_key: 'AUDIO.RATE_LIMIT.MESSAGE',
      message: I18n.t('errors.audio_transcription.rate_limit_exceeded')
    }, status: :too_many_requests
  end

  def validate_groq_token
    return if current_user&.groq_token.present?

    render json: {
      error_type: 'token_missing',
      translation_key: 'AUDIO.TOKEN_MISSING.MESSAGE',
      message: I18n.t('errors.audio_transcription.token_missing')
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

    if params[:file].present?
      validate_upload_file_size(params[:file].size)
      return if performed?

      return
    end

    validate_attachment_file_size
  end

  def validate_upload_file_size(file_size)
    return if file_size <= AUDIO_MAX_SIZE

    render_file_too_large(file_size)
  end

  def validate_attachment_file_size
    attachment = Attachment.find_by(id: params[:attachment_id], account_id: Current.account.id)
    return unless attachment&.file&.attached?

    file_size = attachment.file.blob.byte_size
    validate_upload_file_size(file_size)
  end

  def render_file_too_large(file_size)
    render json: {
      error_type: 'validation_error',
      translation_key: 'AUDIO.FILE_TOO_LARGE',
      message: "File size #{(file_size / 1.megabyte).round(1)}MB exceeds maximum of 25MB"
    }, status: :unprocessable_content
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

  def log_lifecycle(event, attachment_id:, provider:, duration_ms: nil, error: nil)
    payload = {
      event: "audio_transcription.#{event}",
      attachment_id: attachment_id,
      provider: provider,
      user_id: current_user&.id,
      account_id: Current.account&.id
    }
    payload[:duration_ms] = duration_ms if duration_ms
    payload[:error] = error if error
    Rails.logger.info(payload.map { |k, v| "#{k}=#{v}" }.join(' '))
  end

  def elapsed_ms(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  end
end
