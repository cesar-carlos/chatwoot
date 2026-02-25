class Messages::AudioTranscriptionService
  attr_reader :attachment, :message, :account

  def initialize(attachment)
    @attachment = attachment
    @message = attachment.message
    @account = message&.account
  end

  def perform
    return { error: 'Message not found' } if message.blank?
    return { error: 'Transcription disabled for this inbox' } if call_recording_transcription_disabled?
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

  # Call recordings honour the inbox's "Transcribe recordings" setting; ordinary voice notes don't.
  def call_recording_transcription_disabled?
    message.voice_call? && !message.inbox.channel.transcription_enabled?
  end

  def transcribe_audio
    # FORK: check both legacy and canonical keys for idempotency
    transcribed_text = attachment.meta&.dig('transcription', 'text') || attachment.meta&.[]('transcribed_text') || ''
    return transcribed_text if transcribed_text.present?

    transcribed_text = Llm::SpeechToTextService.new(blob: attachment.file.blob, account: account).perform
    update_transcription(transcribed_text)
    transcribed_text
  end

  def update_transcription(transcribed_text)
    return if transcribed_text.blank?

    # FORK: safe merge of meta to preserve other keys, using canonical shape
    current_meta = attachment.meta.to_h
    current_meta['transcribed_text'] = transcribed_text # backward compatibility
    current_meta['transcription'] = {
      'text' => transcribed_text,
      'state' => 'success',
      'provider' => 'openai',
      'model' => WHISPER_MODEL,
      'transcribed_at' => Time.current.to_i,
      'metadata' => {}
    }

    attachment.update!(meta: current_meta)
    message.reload.send_update_event

    return unless ChatwootApp.advanced_search_allowed?

    message.reindex
  end
end
