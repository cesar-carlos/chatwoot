class Custom::Transcription::BaseProvider
  def initialize(*); end

  def transcribe(_attachment, _options = {})
    raise NotImplementedError, "#{self.class.name} must implement #transcribe"
  end
end
