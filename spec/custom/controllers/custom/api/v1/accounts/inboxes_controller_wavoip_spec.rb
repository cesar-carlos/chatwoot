# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Wavoip Inboxes API extensions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:other_channel) { create(:channel_wavoip, account: account, phone_number: '+5511888888888') }
  let(:other_inbox) { other_channel.inbox }

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
    create(:inbox_member, user: agent, inbox: inbox)
    create(:inbox_member, user: outsider, inbox: other_inbox)
  end

  describe 'GET /api/v1/accounts/:account_id/inboxes/:id/wavoip_sdk_bootstrap' do
    it 'returns device_token for inbox member' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/wavoip_sdk_bootstrap",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['device_token']).to eq(channel.device_token)
      expect(response.parsed_body['ice_servers']).to eq(
        [{ 'urls' => ['stun:stun.l.google.com:19302'] }]
      )
    end

    it 'returns unauthorized for agent not in inbox' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/wavoip_sdk_bootstrap",
          headers: outsider.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unauthorized for unauthenticated request' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/wavoip_sdk_bootstrap"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns not found when voice features are disabled' do
      account.disable_features!('channel_wavoip')

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/wavoip_sdk_bootstrap",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/inboxes/:id/regenerate_wavoip_webhook_key' do
    it 'rotates webhook key for administrator' do
      old_key = channel.webhook_key

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/regenerate_wavoip_webhook_key",
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['wavoip_webhook_url']).to include(channel.reload.webhook_key)
      expect(channel.webhook_key).not_to eq(old_key)
    end

    it 'returns unauthorized for non-admin agent' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/regenerate_wavoip_webhook_key",
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/inboxes/:id/test_wavoip_webhook' do
    include ActiveJob::TestHelper

    it 'processes a DEVICE fixture webhook test for administrator' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/test_wavoip_webhook",
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['ok']).to be(true)
      expect(response.parsed_body['webhook_verified']).to be(true)
      expect(channel.reload.webhook_verified?).to be(true)
    end

    it 'returns unauthorized for non-admin agent' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/test_wavoip_webhook",
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/inboxes/:id/set_inbound_calls' do
    it 'disables inbound calls for administrator on a Wavoip inbox' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/set_inbound_calls",
           headers: admin.create_new_auth_token,
           params: { inbound_calls_enabled: false },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(channel.reload.inbound_calls_enabled?).to be false
    end

    it 'enables inbound calls for administrator on a Wavoip inbox' do
      channel.update!(provider_config: channel.provider_config.merge('inbound_calls_enabled' => false))

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/set_inbound_calls",
           headers: admin.create_new_auth_token,
           params: { inbound_calls_enabled: true },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(channel.reload.inbound_calls_enabled?).to be true
    end

    it 'returns unauthorized for non-admin agent' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/set_inbound_calls",
           headers: agent.create_new_auth_token,
           params: { inbound_calls_enabled: false },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(channel.reload.inbound_calls_enabled?).to be true
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/inboxes/:id' do
    it 'updates call_recording_enabled in provider_config for administrator' do
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            headers: admin.create_new_auth_token,
            params: {
              channel: {
                provider_config: {
                  call_recording_enabled: false
                }
              }
            },
            as: :json

      expect(response).to have_http_status(:success)
      expect(channel.reload.call_recording_enabled?).to be(false)
      expect(response.parsed_body['call_recording_enabled']).to be(false)
    end
  end
end
