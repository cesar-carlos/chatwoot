# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::EvolutionGoController, type: :request do
  let(:account) { create(:account) }
  let(:instance_name) { 'test-go-instance' }
  let(:webhook_token) { 'secure-go-webhook-token' }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_name' => instance_name,
        'instance_token' => 'instance-token',
        'webhook_token' => webhook_token
      )
    )
  end
  let(:payload) do
    JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_inbound.json').read)
  end

  before { channel }

  describe 'POST /webhooks/evolution_go/:instance_name' do
    it 'accepts a matching token and enqueues processing with evolution_go_instance_name' do
      expect do
        post "/webhooks/evolution_go/#{instance_name}?token=#{webhook_token}", params: payload
      end.to have_enqueued_job(Webhooks::WhatsappEventsJob).with(
        hash_including(
          'event' => 'MESSAGE',
          'evolution_go_instance_name' => instance_name,
          'channel_id' => channel.id
        )
      )

      expect(response).to have_http_status(:ok)
    end

    it 'does not enqueue ambiguous instance field' do
      post "/webhooks/evolution_go/#{instance_name}?token=#{webhook_token}", params: payload

      job_args = enqueued_jobs.find { |job| job[:job] == Webhooks::WhatsappEventsJob }[:args].first
      expect(job_args).not_to have_key('instance')
      expect(job_args).not_to have_key('instance_name')
    end

    it 'returns unauthorized when token does not match' do
      post "/webhooks/evolution_go/#{instance_name}?token=wrong", params: payload

      expect(response).to have_http_status(:unauthorized)
    end

    it 'accepts Authorization Bearer token' do
      expect do
        post "/webhooks/evolution_go/#{instance_name}",
             params: payload,
             headers: { 'Authorization' => "Bearer #{webhook_token}" }
      end.to have_enqueued_job(Webhooks::WhatsappEventsJob)

      expect(response).to have_http_status(:ok)
    end

    it 'returns not found for an unknown instance' do
      post '/webhooks/evolution_go/unknown-instance?token=abc', params: payload

      expect(response).to have_http_status(:not_found)
    end
  end
end
