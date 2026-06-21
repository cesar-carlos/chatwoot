# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::MediaPayload do
  describe '.publicly_accessible_url?' do
    it 'rejects localhost and private network hosts' do
      expect(described_class.publicly_accessible_url?('http://localhost:3000/files/1')).to be(false)
      expect(described_class.publicly_accessible_url?('http://192.168.1.10/files/1')).to be(false)
    end

    it 'accepts public hosts' do
      expect(described_class.publicly_accessible_url?('https://cdn.example.com/files/1')).to be(true)
    end
  end

  describe '.encode_attachment' do
    it 'returns a data-uri base64 payload' do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new('hello'),
        filename: 'hello.txt',
        content_type: 'text/plain'
      )
      attachment = Attachment.new(file: blob)

      payload = described_class.encode_attachment(attachment)
      expect(payload).to start_with('data:text/plain;base64,')
      expect(Base64.decode64(payload.split(',', 2).last)).to eq('hello')
    end
  end
end
