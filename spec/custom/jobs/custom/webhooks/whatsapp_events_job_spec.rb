# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::WhatsappEventsJob do
  subject(:job) { described_class }

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
        'api_key' => 'TEST-INSTANCE-API-KEY'
      )
    )
  end
  let(:process_service) { instance_double(Whatsapp::IncomingMessageService, perform: nil) }
  let(:connection_service) { instance_double(Custom::Whatsapp::Evolution::ConnectionService, handle_event: nil) }
  let(:contacts_sync_service) { instance_double(Custom::Whatsapp::Evolution::ContactsSyncService, perform: nil) }
  let(:delete_sync_service) { instance_double(Custom::Whatsapp::Evolution::MessageDeleteSyncService, perform: nil) }
  let(:edit_sync_service) { instance_double(Custom::Whatsapp::Evolution::MessageEditSyncService, perform: nil) }

  def load_fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/evolution/#{name}.json").read)
  end

  before do
    channel
    allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)
    allow(Custom::Whatsapp::Evolution::ConnectionService).to receive(:new).and_return(connection_service)
    allow(Custom::Whatsapp::Evolution::ContactsSyncService).to receive(:new).and_return(contacts_sync_service)
    allow(Custom::Whatsapp::Evolution::MessageDeleteSyncService).to receive(:new).and_return(delete_sync_service)
    allow(Custom::Whatsapp::Evolution::MessageEditSyncService).to receive(:new).and_return(edit_sync_service)
    allow(described_class).to receive(:new).and_wrap_original do |original, *args|
      instance = original.call(*args)
      allow(instance).to receive(:with_lock).and_yield
      instance
    end
  end

  describe 'evolution_envelope? routing' do
    it 'detects evolution envelopes by event and instance' do
      job_instance = described_class.new

      expect(job_instance.send(:evolution_envelope?, { event: 'MESSAGES_UPSERT', instance: 'test-instance' })).to be(true)
      expect(job_instance.send(:evolution_envelope?, { object: 'whatsapp_business_account' })).to be(false)
    end

    it 'routes evolution message envelopes through the normalizer before super' do
      envelope = load_fixture('messages_upsert_text')

      job.perform_now(envelope)

      expect(Whatsapp::IncomingMessageService).to have_received(:new).with(
        inbox: channel.inbox,
        params: hash_including(
          contacts: [hash_including(wa_id: '5566996971841')],
          messages: [hash_including(type: 'text', text: { body: 'Oi' })],
          phone_number: channel.phone_number
        )
      )
    end

    it 'routes MESSAGES_UPDATE status through IncomingMessageService' do
      envelope = load_fixture('messages_update_read')

      job.perform_now(envelope)

      expect(Whatsapp::IncomingMessageService).to have_received(:new).with(
        inbox: channel.inbox,
        params: hash_including(
          statuses: [hash_including(id: '3EB0OUTBOUND987654', status: 'read')],
          phone_number: channel.phone_number
        )
      )
    end

    it 'routes live Evolution dotted event names (messages.upsert)' do
      envelope = load_fixture('messages_upsert_text')
      envelope['event'] = 'messages.upsert'

      job.perform_now(envelope)

      expect(Whatsapp::IncomingMessageService).to have_received(:new)
    end

    it 'processes each item in a batch MESSAGES_UPSERT data array' do
      envelope = load_fixture('messages_upsert_batch')

      job.perform_now(envelope)

      expect(Whatsapp::IncomingMessageService).to have_received(:new).twice
    end

    it 'logs when the normalizer skips a message' do
      envelope = load_fixture('messages_upsert_text')
      envelope['data']['key']['fromMe'] = true
      allow(Rails.logger).to receive(:warn)

      job.perform_now(envelope)

      expect(Rails.logger).to have_received(:warn).with(
        '[EVOLUTION] normalizer skipped event=MESSAGES_UPSERT ' \
        'id=3EB00C82C9CE7A7439627F fromMe=true remoteJid=242532642504895@lid'
      )
      expect(Whatsapp::IncomingMessageService).not_to have_received(:new)
    end

    it 'logs and skips when the evolution instance is unknown' do
      allow(Rails.logger).to receive(:warn)

      expect(Rails.logger).to receive(:warn).with('[EVOLUTION] unknown instance=missing-instance')
      expect(Whatsapp::IncomingMessageService).not_to receive(:new)

      job.perform_now(
        event: 'MESSAGES_UPSERT',
        instance: 'missing-instance',
        data: { 'key' => { 'id' => 'ignored' } }
      )
    end
  end

  describe 'contact events' do
    it 'delegates CONTACTS_UPSERT to ContactsSyncService' do
      envelope = load_fixture('contacts_upsert')

      job.perform_now(envelope)

      expect(Custom::Whatsapp::Evolution::ContactsSyncService).to have_received(:new).with(
        channel: channel,
        data: envelope['data']
      )
      expect(contacts_sync_service).to have_received(:perform)
      expect(Whatsapp::IncomingMessageService).not_to have_received(:new)
    end
  end

  describe 'delete and edit events' do
    it 'delegates MESSAGES_DELETE to MessageDeleteSyncService' do
      envelope = load_fixture('messages_delete')

      job.perform_now(envelope)

      expect(Custom::Whatsapp::Evolution::MessageDeleteSyncService).to have_received(:new).with(
        channel: channel,
        data: envelope['data']
      )
      expect(delete_sync_service).to have_received(:perform)
    end

    it 'delegates MESSAGES_EDITED to MessageEditSyncService' do
      envelope = load_fixture('messages_edited')

      job.perform_now(envelope)

      expect(Custom::Whatsapp::Evolution::MessageEditSyncService).to have_received(:new).with(
        channel: channel,
        data: envelope['data']
      )
      expect(edit_sync_service).to have_received(:perform)
    end
  end

  describe 'connection events' do
    it 'delegates CONNECTION_UPDATE to ConnectionService' do
      envelope = load_fixture('connection_update_open')

      job.perform_now(envelope)

      expect(Custom::Whatsapp::Evolution::ConnectionService).to have_received(:new).with(channel: channel)
      expect(connection_service).to have_received(:handle_event).with(envelope)
      expect(Whatsapp::IncomingMessageService).not_to have_received(:new)
    end

    it 'delegates QRCODE_UPDATED to ConnectionService' do
      envelope = load_fixture('qrcode_updated')

      job.perform_now(envelope)

      expect(connection_service).to have_received(:handle_event).with(envelope)
      expect(Whatsapp::IncomingMessageService).not_to have_received(:new)
    end
  end
end
