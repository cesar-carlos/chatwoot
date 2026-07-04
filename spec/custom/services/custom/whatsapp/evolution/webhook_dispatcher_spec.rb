# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::WebhookDispatcher do
  subject(:dispatcher) { described_class.new }

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

  def load_fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/evolution/#{name}.json").read)
  end

  before do
    allow(Custom::Whatsapp::Evolution::MessageMutex).to receive(:with_lock).and_yield
    allow(Custom::Whatsapp::Evolution::InboundMessageProcessor).to receive(:process)
    allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)
  end

  describe '#dispatch' do
    it 'normalizes MESSAGES_UPSERT and delegates to InboundMessageProcessor' do
      envelope = load_fixture('messages_upsert_text')

      dispatcher.dispatch(channel, envelope.symbolize_keys)

      expect(Custom::Whatsapp::Evolution::InboundMessageProcessor).to have_received(:process).with(
        channel,
        hash_including(
          contacts: [hash_including(wa_id: '5566996971841')],
          phone_number: channel.phone_number
        )
      )
    end

    it 'routes Baileys MESSAGES_UPDATE with fromMe to InboundMessageProcessor as status' do
      envelope = {
        'event' => 'MESSAGES_UPDATE',
        'instance' => 'test-instance',
        'data' => {
          'key' => { 'id' => 'BAILEYS-OUT-1', 'remoteJid' => '5511999999999@s.whatsapp.net', 'fromMe' => true },
          'update' => { 'status' => 3 }
        }
      }

      dispatcher.dispatch(channel, envelope.symbolize_keys)

      expect(Custom::Whatsapp::Evolution::InboundMessageProcessor).to have_received(:process).with(
        channel,
        hash_including(
          statuses: [hash_including(id: 'BAILEYS-OUT-1', status: 'delivered')],
          phone_number: channel.phone_number
        )
      )
    end

    it 'routes CONNECTION_UPDATE to ConnectionService' do
      connection_service = instance_double(Custom::Whatsapp::Evolution::ConnectionService, handle_event: nil)
      allow(Custom::Whatsapp::Evolution::ConnectionService).to receive(:new).and_return(connection_service)
      envelope = load_fixture('connection_update_open')

      dispatcher.dispatch(channel, envelope.symbolize_keys)

      expect(connection_service).to have_received(:handle_event).with(hash_including(event: 'CONNECTION_UPDATE'))
    end

    it 'enqueues ContactsSyncJob for CONTACTS_UPSERT' do
      envelope = load_fixture('contacts_upsert')

      expect do
        dispatcher.dispatch(channel, envelope.symbolize_keys)
      end.to have_enqueued_job(Custom::Whatsapp::Evolution::ContactsSyncJob)
        .with(channel.id, envelope['data'])
    end

    it 'logs instance_name for unhandled events' do
      allow(Rails.logger).to receive(:warn)

      dispatcher.dispatch(
        channel,
        { event: 'UNKNOWN_EVENT', instance_name: 'my-instance' }
      )

      expect(Rails.logger).to have_received(:warn).with(
        '[EVOLUTION] unhandled event=UNKNOWN_EVENT instance=my-instance'
      )
    end

    it 'logs instance fallback for unhandled events without instance_name' do
      allow(Rails.logger).to receive(:warn)

      dispatcher.dispatch(channel, { event: 'UNKNOWN_EVENT', instance: 'legacy-instance' })

      expect(Rails.logger).to have_received(:warn).with(
        '[EVOLUTION] unhandled event=UNKNOWN_EVENT instance=legacy-instance'
      )
    end
  end
end
