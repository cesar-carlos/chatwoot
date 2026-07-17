# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Evolution Go Inboxes API extensions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'base_url' => 'https://go.example.com',
        'global_api_key' => 'global-key',
        'instance_token' => 'instance-token',
        'instance_name' => 'test-go-instance',
        'instance_id' => 'inst-1',
        'webhook_token' => 'secret'
      )
    )
  end
  let(:inbox) { channel.inbox }

  around do |example|
    ClimateControl.modify(FRONTEND_URL: 'https://chatwoot.example.com') { example.run }
  end

  before do
    create(:inbox_member, user: agent, inbox: inbox)

    stub_request(:get, %r{https://go\.example\.com/instance/status})
      .to_return(status: 200, body: { message: 'success', data: { connected: false, loggedIn: false } }.to_json)
    stub_request(:get, %r{https://go\.example\.com/instance/info/})
      .to_return(status: 200, body: { message: 'success', data: { name: 'test-go-instance' } }.to_json)
    stub_request(:get, %r{https://go\.example\.com/instance/logs/})
      .to_return(status: 200, body: { message: 'success', data: ['log line'] }.to_json)
    stub_request(:get, %r{https://go\.example\.com/instance/qr})
      .to_return(status: 200, body: { message: 'success', data: { qrcode: 'data:image/png;base64,abc' } }.to_json)
  end

  describe 'POST /api/v1/accounts/:account_id/inboxes/:id/evolution_go_sync_webhook' do
    it 'syncs webhook subscribe list for inbox administrator' do
      stub_request(:post, 'https://go.example.com/instance/connect')
        .to_return(status: 200, body: { message: 'success', data: {} }.to_json)

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/evolution_go_sync_webhook",
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['webhook_subscribe']).to include('MESSAGE', 'HISTORY_SYNC')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/inboxes/:id/evolution_go_pair' do
    it 'returns pairing code for inbox administrator' do
      stub_request(:post, 'https://go.example.com/instance/pair')
        .to_return(
          status: 200,
          body: { message: 'success', data: { PairingCode: 'ABCD-1234' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/evolution_go_pair",
           params: { phone: '5511999999999' },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['pairing_code']).to eq('ABCD-1234')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/inboxes/:id/evolution_go_logout' do
    it 'logs out Evolution Go instance for inbox administrator' do
      stub_request(:delete, 'https://go.example.com/instance/logout')
        .to_return(status: 200, body: { message: 'success', data: {} }.to_json)

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/evolution_go_logout",
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(channel.reload.provider_config['connection_status']).to eq('close')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/inboxes/:id/evolution_go_refresh_contacts' do
    before do
      Redis::Alfred.delete(
        format(Redis::RedisKeys::EVOLUTION_GO_CONTACTS_REFRESH_LOCK, channel_id: channel.id)
      )
    end

    it 'enqueues contact profile refresh for inbox administrator' do
      contact = create(:contact, account: account, phone_number: '+5511888888888')
      create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511888888888')

      enrichment_job = class_double(Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob)
      allow(Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob).to receive(:set)
        .and_return(enrichment_job)
      expect(enrichment_job).to receive(:perform_later).with(
        channel.id,
        contact.id,
        hash_including(force: true)
      )

      release_job = class_double(Custom::Whatsapp::EvolutionGo::ContactsRefreshLockReleaseJob)
      allow(Custom::Whatsapp::EvolutionGo::ContactsRefreshLockReleaseJob).to receive(:set)
        .and_return(release_job)
      allow(release_job).to receive(:perform_later)

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/evolution_go_refresh_contacts",
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['enqueued']).to eq(1)
      expect(response.parsed_body['running']).to be(true)
    end

    it 'returns already_running when lock is held' do
      contact = create(:contact, account: account, phone_number: '+5511888888888')
      create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511888888888')

      Redis::Alfred.set(
        format(Redis::RedisKeys::EVOLUTION_GO_CONTACTS_REFRESH_LOCK, channel_id: channel.id),
        true,
        nx: true,
        ex: 120
      )

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/evolution_go_refresh_contacts",
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('already_running')
      expect(response.parsed_body['remaining_seconds']).to be_between(1, 120)
    end

    it 'returns forbidden for non-administrator' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/evolution_go_refresh_contacts",
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
