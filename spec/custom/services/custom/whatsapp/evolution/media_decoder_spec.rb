# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::MediaDecoder do
  it 'decodes valid base64 payloads' do
    payload = Base64.strict_encode64('hello')

    expect(described_class.decode!(payload)).to eq('hello')
  end

  it 'rejects payloads above the byte limit' do
    expect { described_class.decode!('A' * 64, max_bytes: 10) }.to raise_error(ArgumentError, /byte limit/)
  end
end
