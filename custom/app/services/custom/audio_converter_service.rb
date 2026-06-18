require 'English'

class Custom::AudioConverterService
  AUDIO_MAX_SIZE = 25.megabytes
  FORMATS_REQUIRING_CONVERSION = %w[
    audio/aac audio/x-aac audio/amr audio/x-amr audio/vnd.wave
  ].freeze

  QUALITY_PRESETS = {
    voice: {
      sample_rate: '16000',
      channels: '1',
      filters: 'highpass=200,lowpass=3000',
      quality: '4'
    },
    high_quality: {
      sample_rate: '44100',
      channels: '2',
      filters: 'loudnorm',
      quality: '2'
    },
    small_size: {
      sample_rate: '16000',
      channels: '1',
      filters: 'highpass=100,lowpass=8000',
      quality: '7'
    }
  }.freeze

  attr_reader :audio_file, :preset

  def initialize(audio_file, preset = 'voice')
    @audio_file = audio_file
    @preset = preset.to_sym
  end

  def needs_conversion?
    return false unless audio_file

    FORMATS_REQUIRING_CONVERSION.include?(detect_content_type)
  end

  def needs_preprocessing?
    return false unless audio_file

    needs_conversion? || @preset == :voice
  end

  def convert
    validate_ffmpeg_installed!
    validate_file_size!

    settings = QUALITY_PRESETS[@preset] || QUALITY_PRESETS[:voice]
    temp_output = Tempfile.new(['converted_audio', '.mp3'])
    temp_output.close
    input_path = write_temp_input_file

    command = build_ffmpeg_command(input_path, temp_output.path, settings)
    execute_conversion(command)
    build_converted_file(temp_output.path)
  ensure
    File.delete(input_path) if input_path && File.exist?(input_path)
  end

  def self.ffmpeg_installed?
    system('which ffmpeg > /dev/null 2>&1')
  end

  private

  def detect_content_type
    return normalize_content_type(audio_file.content_type) if audio_file.respond_to?(:content_type)
    return normalize_content_type(audio_file[:type]) if audio_file.is_a?(Hash)

    detect_from_filename
  end

  def detect_from_filename
    extension = if audio_file.respond_to?(:original_filename)
                  File.extname(audio_file.original_filename).downcase.delete('.')
                elsif audio_file.is_a?(Hash)
                  File.extname(audio_file[:filename].to_s).downcase.delete('.')
                else
                  ''
                end

    extension_to_mime = {
      'oga' => 'audio/ogg',
      'opus' => 'audio/opus',
      'aac' => 'audio/aac',
      'amr' => 'audio/amr'
    }

    extension_to_mime[extension] || 'audio/unknown'
  end

  def normalize_content_type(content_type)
    return 'audio/ogg' if %w[audio/oga audio/x-oga].include?(content_type)

    content_type
  end

  def validate_ffmpeg_installed!
    return if self.class.ffmpeg_installed?

    raise StandardError, 'FFmpeg is not installed on this system'
  end

  def validate_file_size!
    file_size = if audio_file.respond_to?(:size)
                  audio_file.size
                elsif audio_file.is_a?(Hash) && audio_file[:tempfile]
                  File.size(audio_file[:tempfile].path)
                else
                  0
                end

    return if file_size <= AUDIO_MAX_SIZE

    raise StandardError, "Audio file too large: #{(file_size / 1.megabyte).round(1)}MB (max: 25MB)"
  end

  def write_temp_input_file
    temp_input = Tempfile.new(['input_audio', detect_extension])
    temp_input.binmode

    if audio_file.respond_to?(:read)
      audio_file.rewind if audio_file.respond_to?(:rewind)
      temp_input.write(audio_file.read)
    elsif audio_file.is_a?(Hash) && audio_file[:tempfile]
      temp_input.write(File.read(audio_file[:tempfile].path))
    end

    temp_input.close
    temp_input.path
  end

  def detect_extension
    if audio_file.respond_to?(:original_filename)
      File.extname(audio_file.original_filename)
    elsif audio_file.is_a?(Hash)
      File.extname(audio_file[:filename].to_s)
    else
      '.audio'
    end
  end

  def build_ffmpeg_command(input_path, output_path, settings)
    [
      'ffmpeg',
      '-i', input_path,
      '-ar', settings[:sample_rate],
      '-ac', settings[:channels],
      '-af', settings[:filters],
      '-q:a', settings[:quality],
      '-y',
      output_path,
      '2>&1'
    ].join(' ')
  end

  def execute_conversion(command)
    output = `#{command}`
    return if $CHILD_STATUS.success?

    Rails.logger.error "FFmpeg conversion failed: #{output}"
    raise StandardError, 'Audio conversion failed'
  end

  def build_converted_file(output_path)
    original_filename = if audio_file.respond_to?(:original_filename)
                          audio_file.original_filename
                        elsif audio_file.is_a?(Hash)
                          audio_file[:filename]
                        else
                          'converted.mp3'
                        end
    base_name = File.basename(original_filename, '.*')

    {
      tempfile: File.open(output_path, 'rb'),
      filename: "#{base_name}.mp3",
      type: 'audio/mp3'
    }
  end
end
