# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::TranscriptionsController < Api::V1::Accounts::BaseController
  AUDIO_MAX_SIZE = 25.megabytes

  before_action :validate_automatic_transcription_not_enabled
  before_action :validate_groq_token
  before_action :validate_rate_limit, only: [:create]
  before_action :validate_audio_file, only: [:create]

  def create
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    log_lifecycle(:start, attachment_id: params[:attachment_id], provider: 'groq')

    check_cache_and_transcribe(started_at)
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

  def validate_automatic_transcription_not_enabled
    return unless automatic_transcription_enabled?

    render json: {
      error_type: 'automatic_transcription_enabled',
      translation_key: 'AUDIO.AUTOMATIC_MODE_ACTIVE.MESSAGE',
      message: I18n.t('errors.audio_transcription.automatic_mode_active')
    }, status: :unprocessable_content
  end

  def automatic_transcription_enabled?
    ActiveModel::Type::Boolean.new.cast(Current.account&.audio_transcriptions)
  end

  def validate_rate_limit
    return if Custom::Transcription::RateLimiter.new(user_id: current_user.id).within_limit?

    render json: {
      error_type: 'rate_limit_exceeded',
      translation_key: 'AUDIO.RATE_LIMIT.MESSAGE',
      message: I18n.t('errors.audio_transcription.rate_limit_exceeded')
    }, status: :too_many_requests
  end

  def check_cache_and_transcribe(started_at)
    attachment = find_attachment
    return if performed?

    if attachment && Custom::TranscriptionMetadata.success_cache?(attachment) && !force_refresh?
      log_lifecycle(:cache_hit, attachment_id: attachment.id, provider: 'groq')
      return render json: Custom::TranscriptionMetadata.format_cached_response(attachment.meta['transcription'])
    end

    transcribe_with_lock(attachment, started_at)
  end

  def transcribe_with_lock(attachment, started_at)
    return transcribe_without_attachment(started_at) unless attachment

    lock_manager = Custom::Transcription::LockManager.new(attachment_id: attachment.id)
    return render_processing_conflict(attachment) unless lock_manager.acquire

    response_data = nil
    begin
      attachment.with_lock do
        attachment.reload
        response_data = locked_transcription_response(attachment, started_at)
      end
    rescue StandardError => e
      save_error(attachment, e.message)
      raise e
    ensure
      lock_manager.release
    end

    render_transcription_response(attachment, response_data)
  end

  def locked_transcription_response(attachment, started_at)
    if Custom::TranscriptionMetadata.success_cache?(attachment) && !force_refresh?
      log_lifecycle(:cache_hit, attachment_id: attachment.id, provider: 'groq')
      return Custom::TranscriptionMetadata.format_cached_response(attachment.meta['transcription'])
    end

    return :processing if Custom::TranscriptionMetadata.read_state(attachment) == 'processing'

    mark_processing(attachment)
    result = perform_transcription(attachment)
    save_success(attachment, result)
    duration_ms = elapsed_ms(started_at)
    log_lifecycle(:success, attachment_id: attachment.id, provider: 'groq', duration_ms: duration_ms)
    result.merge(cached: false)
  end

  def render_transcription_response(attachment, response_data)
    return render_processing_conflict(attachment) if response_data == :processing

    render json: response_data
  end

  def transcribe_without_attachment(started_at)
    result = perform_transcription(nil)
    duration_ms = elapsed_ms(started_at)
    log_lifecycle(:success, attachment_id: nil, provider: 'groq', duration_ms: duration_ms)
    render json: result.merge(cached: false)
  end

  def render_processing_conflict(attachment)
    render json: {
      error_type: 'transcription_in_progress',
      translation_key: 'AUDIO.TRANSCRIPTION.IN_PROGRESS',
      message: I18n.t('errors.audio_transcription.in_progress'),
      state: Custom::TranscriptionMetadata.read_state(attachment)
    }, status: :conflict
  end

  def mark_processing(attachment)
    Custom::TranscriptionMetadata.write_transcription(attachment, {
                                                        state: 'processing',
                                                        provider: 'groq',
                                                        started_at: Time.current.to_i
                                                      })
    notify_message_update(attachment)
  end

  def save_success(attachment, transcription_data)
    Custom::TranscriptionMetadata.write_transcription(attachment, transcription_data)
    notify_message_update(attachment)
  end

  def save_error(attachment, error_message)
    Custom::TranscriptionMetadata.write_transcription(attachment, {
                                                        state: 'error',
                                                        provider: 'groq',
                                                        error: error_message,
                                                        failed_at: Time.current.to_i
                                                      })
    notify_message_update(attachment)
  end

  def notify_message_update(attachment)
    message = attachment.message
    return unless message

    message.reload.send_update_event
    message.reindex if ChatwootApp.advanced_search_allowed?
  end

  def find_attachment
    return nil if params[:attachment_id].blank?

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

  def force_refresh?
    params[:force_refresh].to_s == 'true'
  end

  def perform_transcription(attachment)
    transcription_provider.transcribe(
      attachment,
      file: params[:file]
    )
  end

  def transcription_provider
    Custom::Transcription::GroqProvider.new(
      user: current_user,
      params: {
        model: params[:model],
        language: params[:language],
        prompt: params[:prompt],
        quality_preset: params[:quality_preset]
      }
    )
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
# rubocop:enable Metrics/ClassLength
