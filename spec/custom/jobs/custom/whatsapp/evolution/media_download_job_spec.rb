# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::MediaDownloadJob, type: :job do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'base_url' => 'http://localhost:8080',
        'instance_name' => 'test-instance',
        'api_key' => 'TEST-KEY'
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
      '_evolution_message' => {
        'key' => { 'id' => 'MEDIA-MSG-1', 'remoteJid' => '5511999999999@s.whatsapp.net' },
        'message' => { 'imageMessage' => { 'mimetype' => 'image/jpeg' } }
      }
    }
  end
  let(:service) { instance_double(Custom::Whatsapp::Evolution::MediaAttachmentService, perform: true) }

  before do
    allow(Custom::Whatsapp::Evolution::MediaAttachmentService).to receive(:new).and_return(service)
  end

  it 'delegates to MediaAttachmentService' do
    described_class.perform_now(channel.id, message.id, attachment_payload, 'image')

    expect(Custom::Whatsapp::Evolution::MediaAttachmentService).to have_received(:new).with(
      channel: channel,
      message: message,
      attachment_payload: attachment_payload.with_indifferent_access,
      message_type: 'image'
    )
    expect(service).to have_received(:perform)
  end

  it 'no-ops when the channel is missing' do
    expect(Custom::Whatsapp::Evolution::MediaAttachmentService).not_to receive(:new)

    described_class.perform_now(-1, message.id, attachment_payload, 'image')
  end

  it 'no-ops when the message already has attachments' do
    message.attachments.create!(account: account, file_type: :image, external_url: 'https://example.com/existing.jpg')

    expect(Custom::Whatsapp::Evolution::MediaAttachmentService).not_to receive(:new)

    described_class.perform_now(channel.id, message.id, attachment_payload, 'image')
  end

  it 'releases the media lock after a service failure so retries can run' do
    allow(service).to receive(:perform).and_raise(StandardError, 'download failed')
    lock_key = format(Redis::RedisKeys::EVOLUTION_MEDIA_DOWNLOAD_LOCK, message_id: message.id)

    expect do
      described_class.perform_now(channel.id, message.id, attachment_payload, 'image')
    end.to raise_error(StandardError, 'download failed')

    expect(Redis::Alfred.get(lock_key)).to be_nil
    expect(Redis::Alfred.set(lock_key, true, nx: true, ex: 60)).to be(true)
  end

  it 'raises LockAcquisitionError when the media lock is busy' do
    lock_key = format(Redis::RedisKeys::EVOLUTION_MEDIA_DOWNLOAD_LOCK, message_id: message.id)
    Redis::Alfred.set(lock_key, true, nx: true, ex: 60)

    expect do
      described_class.perform_now(channel.id, message.id, attachment_payload, 'image')
    end.to raise_error(MutexApplicationJob::LockAcquisitionError, /media download lock busy/)

    expect(Custom::Whatsapp::Evolution::MediaAttachmentService).not_to have_received(:new)
  end
end
