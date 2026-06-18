require 'rails_helper'

RSpec.describe Custom::AudioConverterService do
  let(:tempfile) do
    file = Tempfile.new(['sample', '.mp3'])
    file.write('fake audio data')
    file.rewind
    file
  end

  after do
    tempfile.close
    tempfile.unlink
  end

  describe '#needs_conversion?' do
    it 'returns true for aac content type' do
      service = described_class.new(build_upload('sample.aac', 'audio/aac'))
      expect(service.needs_conversion?).to be(true)
    end

    it 'returns true for amr content type' do
      service = described_class.new(build_upload('sample.amr', 'audio/amr'))
      expect(service.needs_conversion?).to be(true)
    end

    it 'returns false for mp3 content type' do
      service = described_class.new(build_upload('sample.mp3', 'audio/mpeg'))
      expect(service.needs_conversion?).to be(false)
    end

    it 'returns false for ogg content type' do
      service = described_class.new(build_upload('sample.ogg', 'audio/ogg'))
      expect(service.needs_conversion?).to be(false)
    end

    it 'detects oga extension as ogg mime for conversion check' do
      service = described_class.new(build_upload('sample.oga', 'audio/oga'))
      expect(service.needs_conversion?).to be(false)
    end
  end

  describe '#needs_preprocessing?' do
    it 'returns true for voice preset even when mp3 does not need conversion' do
      service = described_class.new(build_upload('sample.mp3', 'audio/mpeg'), 'voice')
      expect(service.needs_preprocessing?).to be(true)
    end

    it 'returns true for unsupported formats regardless of preset' do
      service = described_class.new(build_upload('sample.aac', 'audio/aac'), 'high_quality')
      expect(service.needs_preprocessing?).to be(true)
    end
  end

  describe '#convert' do
    before do
      allow(described_class).to receive(:ffmpeg_installed?).and_return(true)
      allow_any_instance_of(described_class).to receive(:execute_conversion) # rubocop:disable RSpec/AnyInstance
    end

    it 'returns converted mp3 hash' do
      service = described_class.new(build_upload('sample.aac', 'audio/aac'))
      result = service.convert

      expect(result[:type]).to eq('audio/mp3')
      expect(result[:filename]).to eq('sample.mp3')
      expect(result[:tempfile]).to be_a(File)
      result[:tempfile].close
    end
  end

  def build_upload(filename, content_type)
    ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: filename,
      type: content_type
    )
  end
end
