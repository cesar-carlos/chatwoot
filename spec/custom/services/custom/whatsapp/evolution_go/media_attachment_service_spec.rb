# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::MediaAttachmentService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_name' => 'test-go-instance',
        'instance_token' => 'token'
      )
    )
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
  let(:api_client) { instance_double(Custom::Whatsapp::EvolutionGo::ApiClient) }
  let(:evolution_go_message) do
    {
      key: { id: 'MEDIA-1' },
      message: { documentMessage: { mimetype: 'text/plain', fileName: 'anotacoes.txt' } }
    }
  end

  before do
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).and_return(api_client)
  end

  it 'creates an attachment from nested data.base64 response' do
    file_bytes = Base64.strict_encode64('hello attachment')
    allow(api_client).to receive(:download_media).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'data' => {
            'base64' => "data:text/plain;base64,#{file_bytes}",
            'mimetype' => 'text/plain',
            'fileName' => 'anotacoes.txt'
          }
        }
      )
    )

    described_class.new(
      channel: channel,
      message: message,
      attachment_payload: { _evolution_go_message: evolution_go_message },
      message_type: 'document'
    ).perform

    expect(message.attachments.count).to eq(1)
    expect(message.attachments.first.file_type).to eq('file')
    expect(message.reload.content_attributes['evolution_go_media_failed']).to be(false)
  end

  it 'marks media failure when download response has no base64 payload' do
    allow(api_client).to receive(:download_media).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'data' => {} }
      )
    )

    described_class.new(
      channel: channel,
      message: message,
      attachment_payload: { _evolution_go_message: evolution_go_message },
      message_type: 'document'
    ).perform

    expect(message.attachments.count).to eq(0)
    expect(message.reload.content_attributes['evolution_go_media_failed']).to be(true)
    expect(message.content_attributes['evolution_go_media_error']).to eq('Empty media response from Evolution Go')
  end
end
