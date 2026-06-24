# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::WebhookDispatcher do
  subject(:dispatcher) { described_class.new(job: job) }

  let(:job) { instance_double(Webhooks::WhatsappEventsJob) }
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
    allow(job).to receive(:send).with(:process_events, anything, anything)
    allow(job).to receive(:send).with(:with_lock, anything, anything).and_yield
    allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)
  end

  describe '#dispatch' do
    it 'normalizes MESSAGES_UPSERT and delegates to the job process_events' do
      envelope = load_fixture('messages_upsert_text')

      dispatcher.dispatch(channel, envelope.symbolize_keys)

      expect(job).to have_received(:send).with(
        :process_events,
        channel,
        hash_including(
          contacts: [hash_including(wa_id: '5566996971841')],
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
  end
end
