# rubocop:disable Metrics/ClassLength
class Custom::Transcription::Orchestrator
  Result = Struct.new(:status, :body, keyword_init: true)

  def initialize(user_context:, account:, params:)
    @user_context = user_context
    @user = user_context[:user]
    @account = account
    @params = params
  end

  def perform
    attachment = resolve_attachment
    return attachment if attachment.is_a?(Result)

    if attachment
      return cached_result(attachment) if cached_success?(attachment)

      transcribe_with_lock(attachment)
    else
      transcribe_without_attachment
    end
  end

  private

  attr_reader :user_context, :user, :account, :params

  def resolve_attachment
    return nil if params[:attachment_id].blank?

    attachment = Attachment.find_by(id: params[:attachment_id], account_id: account.id)
    return not_found_result if attachment.nil?
    return forbidden_result unless authorized_for_attachment?(attachment)

    attachment
  end

  def authorized_for_attachment?(attachment)
    conversation = attachment.message&.conversation
    return false unless conversation

    ConversationPolicy.new(user_context, conversation).show?
  end

  def cached_success?(attachment)
    Custom::TranscriptionMetadata.success_cache?(attachment) && !force_refresh?
  end

  def cached_result(attachment)
    log_lifecycle(:cache_hit, attachment_id: attachment.id)
    Result.new(
      status: :ok,
      body: Custom::TranscriptionMetadata.format_cached_response(attachment.meta['transcription'])
    )
  end

  # rubocop:disable Metrics/MethodLength
  def transcribe_with_lock(attachment)
    lock_manager = Custom::Transcription::LockManager.new(attachment_id: attachment.id)
    recover_stale_processing!(attachment)

    unless lock_manager.acquire
      if Custom::TranscriptionMetadata.actively_processing?(
        attachment,
        lock_manager: lock_manager,
        force_refresh: force_refresh?
      )
        return processing_conflict_result(attachment)
      end

      Custom::TranscriptionMetadata.clear_processing_state!(attachment)
      return processing_conflict_result(attachment) unless lock_manager.acquire
    end

    response_data = nil
    begin
      attachment.with_lock do
        attachment.reload
        response_data = locked_transcription_response(attachment, lock_manager)
      end
    rescue StandardError => e
      save_error(attachment, e.message)
      raise e
    ensure
      lock_manager.release
    end

    return processing_conflict_result(attachment) if response_data == :processing

    Result.new(status: :ok, body: response_data)
  end
  # rubocop:enable Metrics/MethodLength

  # rubocop:disable Metrics/MethodLength
  def locked_transcription_response(attachment, lock_manager)
    if cached_success?(attachment)
      log_lifecycle(:cache_hit, attachment_id: attachment.id)
      return Custom::TranscriptionMetadata.format_cached_response(attachment.meta['transcription'])
    end

    if force_refresh?
      clear_refreshable_state!(attachment)
    elsif Custom::TranscriptionMetadata.stale_processing?(attachment)
      Custom::TranscriptionMetadata.clear_processing_state!(attachment)
    elsif Custom::TranscriptionMetadata.read_state(attachment) == 'processing'
      return :processing if Custom::TranscriptionMetadata.actively_processing?(
        attachment,
        lock_manager: lock_manager,
        force_refresh: false
      )

      Custom::TranscriptionMetadata.clear_processing_state!(attachment)
    end

    mark_processing(attachment)
    result = perform_transcription(attachment)
    save_success(attachment, result)
    log_lifecycle(:success, attachment_id: attachment.id)
    result.merge(cached: false)
  end
  # rubocop:enable Metrics/MethodLength

  def transcribe_without_attachment
    result = perform_transcription(nil)
    log_lifecycle(:success, attachment_id: nil)
    Result.new(status: :ok, body: result.merge(cached: false))
  end

  def clear_refreshable_state!(attachment)
    state = Custom::TranscriptionMetadata.read_state(attachment)
    return unless state.in?(%w[processing error])

    Custom::TranscriptionMetadata.clear_processing_state!(attachment)
  end

  def recover_stale_processing!(attachment)
    return unless Custom::TranscriptionMetadata.stale_processing?(attachment)

    Custom::TranscriptionMetadata.clear_processing_state!(attachment)
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

  def perform_transcription(attachment)
    transcription_provider.transcribe(
      attachment,
      file: params[:file]
    )
  end

  def transcription_provider
    Custom::Transcription::GroqProvider.new(
      user: user,
      params: {
        model: params[:model],
        language: params[:language],
        prompt: params[:prompt],
        quality_preset: params[:quality_preset]
      }
    )
  end

  def force_refresh?
    params[:force_refresh].to_s == 'true'
  end

  def not_found_result
    Result.new(
      status: :not_found,
      body: {
        error_type: 'attachment_not_found',
        message: "Attachment with id #{params[:attachment_id]} not found or does not belong to this account"
      }
    )
  end

  def forbidden_result
    Result.new(
      status: :forbidden,
      body: {
        error_type: 'forbidden',
        translation_key: 'AUDIO.TRANSCRIPTION.FORBIDDEN',
        message: I18n.t('errors.audio_transcription.forbidden')
      }
    )
  end

  def processing_conflict_result(attachment)
    Result.new(
      status: :conflict,
      body: {
        error_type: 'transcription_in_progress',
        translation_key: 'AUDIO.TRANSCRIPTION.IN_PROGRESS',
        message: I18n.t('errors.audio_transcription.in_progress'),
        state: Custom::TranscriptionMetadata.read_state(attachment)
      }
    )
  end

  def log_lifecycle(event, attachment_id:, error: nil)
    payload = {
      event: "audio_transcription.#{event}",
      attachment_id: attachment_id,
      provider: 'groq',
      user_id: user&.id,
      account_id: account&.id
    }
    payload[:error] = error if error
    Rails.logger.info(payload.map { |k, v| "#{k}=#{v}" }.join(' '))
  end
end
# rubocop:enable Metrics/ClassLength
