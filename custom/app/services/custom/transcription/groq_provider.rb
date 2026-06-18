class Custom::Transcription::GroqProvider < Custom::Transcription::BaseProvider
  include Integrations::LlmInstrumentation

  attr_reader :user, :params

  def initialize(user:, params: {})
    super()
    @user = user
    @params = params
  end

  def transcribe(attachment, options = {})
    instrument_audio_transcription(instrumentation_params(attachment)) do
      if attachment
        groq_service.transcribe_attachment(attachment)
      else
        groq_service.transcribe_upload(options[:file])
      end
    end
  end

  private

  def groq_service
    Custom::Groq::AudioTranscriptionService.new(user: user, params: params)
  end

  def instrumentation_params(attachment)
    {
      span_name: 'llm.messages.groq_audio_transcription',
      model: params[:model] || Custom::Groq::AudioTranscriptionService::DEFAULT_MODEL,
      account_id: attachment&.account_id,
      feature_name: 'groq_audio_transcription',
      file_path: attachment&.id
    }
  end
end
