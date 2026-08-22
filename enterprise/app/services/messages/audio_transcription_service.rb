class Messages::AudioTranscriptionService
  attr_reader :attachment, :message, :account

  def initialize(attachment)
    @attachment = attachment
    @message = attachment.message
    @account = message&.account
  end

  def perform
    return { error: 'Message not found' } if message.blank?
    return { error: 'Transcription limit exceeded' } unless Llm::SpeechToTextService.available_for?(account)
    return { error: 'Audio too large for transcription' } if Llm::SpeechToTextService.too_large?(attachment.file&.blob)

    transcriptions = transcribe_audio
    Rails.logger.info "Audio transcription successful: #{transcriptions}"
    { success: true, transcriptions: transcriptions }
  rescue Faraday::UnauthorizedError
    Rails.logger.warn('Skipping audio transcription: OpenAI configuration is invalid or disabled (401 Unauthorized).')
    { error: 'OpenAI configuration is invalid or disabled (401)' }
  end

  private

  def transcribe_audio
    # FORK: unified transcript reader for idempotency
    transcribed_text = Custom::TranscriptionMetadata.read_text(attachment)
    return transcribed_text if transcribed_text.present?

    speech_service = Llm::SpeechToTextService.new(blob: attachment.file.blob, account: account)
    transcribed_text = speech_service.perform
    update_transcription(transcribed_text, speech_service.transcription_model)
    transcribed_text
  end

  def update_transcription(transcribed_text, transcription_model)
    return if transcribed_text.blank?

    # FORK: safe merge via unified metadata writer
    Custom::TranscriptionMetadata.write_transcription(attachment, {
                                                        text: transcribed_text,
                                                        state: 'success',
                                                        provider: 'openai',
                                                        model: transcription_model,
                                                        transcribed_at: Time.current.to_i,
                                                        metadata: {}
                                                      })
    message.reload.send_update_event

    return unless ChatwootApp.advanced_search_allowed?

    message.reindex
  end
end
