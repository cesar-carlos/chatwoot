# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::CorruptMediaRepair do
  def corrupt_from_data_url(data_url)
    Base64.decode64(data_url)
  end

  it 'detects blobs produced by decoding a data-URL as raw base64' do
    pdf = '%PDF-1.4 hello'
    data_url = "data:application/pdf;base64,#{Base64.strict_encode64(pdf)}"
    corrupt = corrupt_from_data_url(data_url)

    expect(described_class.corrupt_data_url_blob?(corrupt)).to be(true)
    expect(described_class.corrupt_data_url_blob?(pdf)).to be(false)
  end

  it 'recovers PDF bytes and mime type from a corrupt blob' do
    pdf = "%PDF-1.4\n% content"
    data_url = "data:application/pdf;base64,#{Base64.strict_encode64(pdf)}"
    recovered = described_class.recover(corrupt_from_data_url(data_url))

    expect(recovered[:mime_type]).to eq('application/pdf')
    expect(recovered[:bytes]).to eq(pdf)
    expect(described_class.valid_for_content_type?(recovered[:bytes], 'application/pdf')).to be(true)
  end

  it 'recovers JPEG bytes from a corrupt blob' do
    jpeg = "\xFF\xD8\xFF\xE0\x00\x10JFIF".b
    data_url = "data:image/jpeg;base64,#{Base64.strict_encode64(jpeg)}"
    recovered = described_class.recover(corrupt_from_data_url(data_url))

    expect(recovered[:mime_type]).to eq('image/jpeg')
    expect(recovered[:bytes].byteslice(0, 2)).to eq("\xFF\xD8".b)
  end
end
