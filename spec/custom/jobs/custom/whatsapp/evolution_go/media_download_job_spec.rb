# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::MediaDownloadJob, type: :job do
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
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999999999') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      sender: contact,
      source_id: 'MEDIA-MSG-1',
      content: 'Photo caption'
    )
  end
  let(:attachment_payload) do
    {
      'caption' => 'Photo caption',
      'filename' => 'photo.jpg',
      'mimetype' => 'image/jpeg',
      '_evolution_go_message' => {
        'key' => { 'id' => 'MEDIA-MSG-1' },
        'message' => { 'imageMessage' => { 'mimetype' => 'image/jpeg' } }
      }
    }
  end
  let(:service) { instance_double(Custom::Whatsapp::EvolutionGo::MediaAttachmentService, perform: true) }

  before do
    allow(Custom::Whatsapp::EvolutionGo::MediaAttachmentService).to receive(:new).and_return(service)
  end

  it 'marks the message failed when download retries are exhausted' do
    allow(service).to receive(:perform).and_raise(StandardError, 'download failed')
    job = described_class.new(channel.id, message.id, attachment_payload, 'image')
    job.exception_executions['[StandardError]'] = 4

    job.perform_now

    expect(message.reload.content_attributes['evolution_go_media_failed']).to be(true)
    expect(message.content_attributes['evolution_go_media_error']).to eq('download failed')
  end

  it 'does not flag a message that already has an attachment' do
    message.attachments.create!(account: account, file_type: :image, external_url: 'https://example.com/existing.jpg')
    job = described_class.new(channel.id, message.id, attachment_payload, 'image')

    job.mark_download_exhausted!(StandardError.new('download failed'))

    expect(message.reload.content_attributes.to_h['evolution_go_media_failed']).not_to be(true)
  end
end
