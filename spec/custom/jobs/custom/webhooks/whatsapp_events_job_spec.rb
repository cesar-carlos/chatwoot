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

  def load_fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/evolution/#{name}.json").read)
  end

  before do
    channel
    allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)
    allow(Custom::Whatsapp::Evolution::ConnectionService).to receive(:new).and_return(connection_service)
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
