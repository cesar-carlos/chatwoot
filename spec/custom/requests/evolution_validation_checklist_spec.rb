# frozen_string_literal: true

require 'rails_helper'

# Automated coverage for validation-checklist.md §2–4.
# Real-instance smoke: bundle exec rake evolution:validate_checklist (requires EVOLUTION_* env).
RSpec.describe 'Evolution validation checklist §2–4', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:instance_name) { 'checklist-instance' }
  let(:api_key) { 'TEST-INSTANCE-API-KEY' }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      phone_number: '+55000f34332563f',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'instance_name' => instance_name,
        'api_key' => api_key
      )
    )
  end
  let(:inbox) { channel.inbox }

  def load_fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/evolution/#{name}.json").read)
  end

  before do
    channel
    allow_any_instance_of(Webhooks::WhatsappEventsJob).to receive(:with_lock).and_yield # rubocop:disable RSpec/AnyInstance
  end

  describe '§2 webhook inbound' do
    let(:payload) do
      load_fixture('messages_upsert_text').merge('apikey' => api_key, 'instance' => instance_name)
    end

    it 'accepts webhook and enqueues processing' do
      expect do
        post "/webhooks/evolution/#{instance_name}", params: payload
      end.to have_enqueued_job(Webhooks::WhatsappEventsJob)

      expect(response).to have_http_status(:ok)
    end

    it 'creates conversation message when the job runs' do
      expect do
        Webhooks::WhatsappEventsJob.perform_now(payload)
      end.to change(Message, :count).by(1)

      message = Message.last
      expect(message.inbox).to eq(inbox)
      expect(message.content).to eq('Oi')
      expect(message.source_id).to eq('3EB00C82C9CE7A7439627F')
    end
  end

  describe '§3 outbound Chatwoot → Evolution' do
    let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }
    let(:send_response) do
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: JSON.parse(
          Rails.root.join('spec/fixtures/evolution/send_text_response.json').read
        )
      )
    end
    let(:service) { Custom::Whatsapp::Providers::EvolutionService.new(whatsapp_channel: channel) }

    before do
      allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:for_channel).with(channel).and_return(api_client)
      allow(api_client).to receive(:send_text).and_return(send_response)
    end

    it 'returns Baileys key.id without WAID prefix' do
      contact = create(:contact, account: account, phone_number: '+5566996971841')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566996971841')
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        content: 'reply from agent'
      )

      message_id = service.send_message(contact_inbox.source_id, message)

      expect(message_id).to eq('3EB0C6D7F8BC03700FBB95')
      expect(message_id).not_to start_with('WAID:')
    end
  end

  describe '§4 connection UI API' do
    let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }

    before do
      allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:for_channel).and_return(api_client)
      allow(api_client).to receive(:connection_state).and_return(
        instance_double(
          HTTParty::Response,
          success?: true,
          parsed_response: JSON.parse(
            Rails.root.join('spec/fixtures/evolution/connection_state_connecting.json').read
          )
        )
      )
    end

    it 'returns QR payload after QRCODE_UPDATED webhook (polling path)' do
      envelope = load_fixture('qrcode_updated').merge('instance' => instance_name)
      Webhooks::WhatsappEventsJob.perform_now(envelope)

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/evolution_connection",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['qrcode_base64']).to start_with('data:image/png;base64,')
      expect(body['connection_status']).to eq('connecting')
    end

    it 'updates connection_status to open after CONNECTION_UPDATE webhook' do
      envelope = load_fixture('connection_update_open').merge('instance' => instance_name)
      Webhooks::WhatsappEventsJob.perform_now(envelope)

      channel.reload
      expect(channel.provider_config['connection_status']).to eq('open')
      expect(channel.phone_number).to eq('+556681128433')
    end
  end
end
