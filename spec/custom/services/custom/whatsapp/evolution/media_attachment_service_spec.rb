# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::MediaAttachmentService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'instance_name' => 'test-instance',
        'api_key' => 'TEST-KEY'
      )
    )
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
  let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }
  let(:evolution_message) { { key: { id: 'MEDIA-1' }, message: { imageMessage: { mimetype: 'image/jpeg' } } } }

  before do
    allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:for_channel).and_return(api_client)
  end

  it 'creates an attachment from base64 media response' do
    png_bytes = Base64.strict_encode64('fake-image')
    allow(api_client).to receive(:get_base64_from_media_message).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'base64' => png_bytes,
          'mimetype' => 'image/jpeg',
          'fileName' => 'photo.jpg'
        }
      )
    )

    described_class.new(
      channel: channel,
      message: message,
      attachment_payload: { _evolution_message: evolution_message },
      message_type: 'image'
    ).perform

    expect(message.attachments.count).to eq(1)
    expect(message.attachments.first.file_type).to eq('image')
  end

  it 'marks media failure when evolution message is missing' do
    described_class.new(
      channel: channel,
      message: message,
      attachment_payload: {},
      message_type: 'image'
    ).perform

    expect(message.attachments.count).to eq(0)
  end
end
