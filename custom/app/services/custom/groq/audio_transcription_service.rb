class Custom::Groq::AudioTranscriptionService
  GROQ_API_URL = 'https://api.groq.com/openai/v1/audio/transcriptions'.freeze
  DEFAULT_MODEL = 'whisper-large-v3-turbo'.freeze
  REQUEST_TIMEOUT = 60
  OPEN_TIMEOUT = 10

  attr_reader :user, :params

  def initialize(user:, params: {})
    @user = user
    @params = params
  end

  def transcribe_attachment(attachment)
    source_audio_file = fetch_audio_from_attachment(attachment)
    transcribe_file(source_audio_file)
  ensure
    cleanup_temp_file(source_audio_file) if source_audio_file.is_a?(Hash)
  end

  def transcribe_upload(file)
    transcribe_file(file)
  end

  private

  def transcribe_file(source_audio_file)
    prepared_audio_file = prepare_audio_file(source_audio_file)

    groq_response = send_to_groq_api(prepared_audio_file)
    parse_groq_response(groq_response)
  ensure
    cleanup_temp_file(prepared_audio_file) if prepared_audio_file.is_a?(Hash) && prepared_audio_file != source_audio_file
  end

  def prepare_audio_file(audio_file)
    converter = Custom::AudioConverterService.new(audio_file, quality_preset)

    audio_type = audio_file.is_a?(Hash) ? audio_file[:type] : audio_file.content_type
    Rails.logger.info "Audio file before conversion check: type=#{audio_type} needs_conversion=#{converter.needs_conversion?}"

    return audio_file unless converter.needs_preprocessing?

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
      req.headers['Authorization'] = "Bearer #{user.groq_token}"
      req.body = payload
    end

    handle_groq_response(response)
  end

  def build_groq_payload(audio_file)
    file_io, filename, content_type = extract_file_params(audio_file)

    Rails.logger.info "Building Groq payload: filename=#{filename} content_type=#{content_type}"

    payload = {
      file: Faraday::UploadIO.new(file_io, content_type, filename),
      model: params[:model] || DEFAULT_MODEL,
      response_format: 'verbose_json',
      temperature: '0.0'
    }

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

  def cleanup_temp_file(audio_file_hash)
    return unless audio_file_hash.is_a?(Hash) && audio_file_hash[:tempfile]

    audio_file_hash[:tempfile].close
    FileUtils.rm_f(audio_file_hash[:tempfile].path)
  end

  def validate_ffmpeg_availability!
    return if Custom::AudioConverterService.ffmpeg_installed?

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
    return 'audio/ogg' if %w[audio/oga audio/x-oga].include?(content_type)

    content_type
  end

  def normalized_filename(filename, content_type)
    return filename unless content_type == 'audio/ogg'
    return filename unless filename.to_s.downcase.end_with?('.oga')

    filename.to_s.sub(/\.oga\z/i, '.ogg')
  end
end
