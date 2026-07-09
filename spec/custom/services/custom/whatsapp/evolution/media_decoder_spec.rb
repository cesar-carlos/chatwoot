# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::MediaDecoder do
  it 'decodes valid base64 payloads' do
    payload = Base64.strict_encode64('hello')

    expect(described_class.decode!(payload)).to eq('hello')
  end

  it 'strips Evolution Go data-URL prefixes before decoding' do
    pdf = '%PDF-1.4 content'
    data_url = "data:application/pdf;base64,#{Base64.strict_encode64(pdf)}"

    expect(described_class.decode!(data_url)).to eq(pdf)
    expect(described_class.mime_type_from_data_url(data_url)).to eq('application/pdf')
  end

  it 'rejects payloads above the byte limit' do
    expect { described_class.decode!('A' * 64, max_bytes: 10) }.to raise_error(ArgumentError, /byte limit/)
  end
end
