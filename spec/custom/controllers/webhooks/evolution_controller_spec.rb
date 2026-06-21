# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::EvolutionController, type: :request do
  let(:account) { create(:account) }
  let(:instance_name) { 'test-instance' }
  let(:api_key) { 'TEST-INSTANCE-API-KEY' }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'instance_name' => instance_name,
        'api_key' => api_key
      )
    )
  end
  let(:payload) do
    JSON.parse(Rails.root.join('spec/fixtures/evolution/messages_upsert_text.json').read)
        .merge('apikey' => api_key)
  end

  before { channel }

  describe 'POST /webhooks/evolution/:instance_name' do
    it 'accepts a matching apikey and enqueues processing' do
      expect do
        post "/webhooks/evolution/#{instance_name}", params: payload
      end.to have_enqueued_job(Webhooks::WhatsappEventsJob).with(
        hash_including('event' => 'MESSAGES_UPSERT', 'instance_name' => instance_name)
      )

      expect(response).to have_http_status(:ok)
    end

    it 'returns unauthorized when apikey does not match' do
      post "/webhooks/evolution/#{instance_name}", params: payload.merge('apikey' => 'wrong-key')

      expect(response).to have_http_status(:unauthorized)
    end

    it 'accepts apikey with surrounding whitespace' do
      expect do
        post "/webhooks/evolution/#{instance_name}",
             params: payload.merge('apikey' => "  #{api_key}  ")
      end.to have_enqueued_job(Webhooks::WhatsappEventsJob)

      expect(response).to have_http_status(:ok)
    end

    it 'returns not found for an unknown instance' do
      post '/webhooks/evolution/unknown-instance', params: payload

      expect(response).to have_http_status(:not_found)
    end
  end
end
