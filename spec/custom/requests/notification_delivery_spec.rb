require 'rails_helper'

RSpec.describe 'Notification delivery API', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:headers) { user.create_new_auth_token }
  let(:endpoint) { 'https://push.example.test/device' }
  let(:key) { OpenSSL::PKey::EC.generate('prime256v1').public_key.to_octet_string(:uncompressed) }
  let(:attributes) { { endpoint: endpoint, p256dh: Base64.urlsafe_encode64(key, padding: false), auth: Base64.strict_encode64('a' * 16) } }
  let(:conversation) { create(:conversation, account: account) }
  let(:notification) { create(:notification, user: user, account: account, primary_actor: conversation) }

  def register(attributes)
    post '/api/v1/notification_subscriptions', params: {
      notification_subscription: { subscription_type: 'browser_push', subscription_attributes: attributes }
    }, headers: headers, as: :json
  end

  describe 'browser registration' do
    it 'accepts compatible Base64 and Base64URL encryption keys' do
      register(attributes)
      expect(response).to have_http_status(:ok)
      expect(user.notification_subscriptions.find_by!(identifier: endpoint).subscription_attributes).to include(attributes.stringify_keys)
    end

    it 'rejects missing keys without persisting a subscription' do
      register(endpoint: endpoint)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.notification_subscriptions).to be_empty
    end

    it 'rejects malformed subscription envelopes without persisting' do
      ['invalid', [], nil].each do |input|
        post '/api/v1/notification_subscriptions', params: { notification_subscription: input }, headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(user.notification_subscriptions).to be_empty
    end

    it 'rejects an invalid curve point' do
      register(attributes.merge(p256dh: Base64.strict_encode64("\x04#{'a' * 64}")))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.notification_subscriptions).to be_empty
    end

    it 'does not transfer an existing device when input validation fails' do
      other = create(:notification_subscription, identifier: endpoint)
      register(endpoint: endpoint)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(other.reload.user_id).not_to eq(user.id)
    end

    it 'rejects short authentication secrets' do
      register(attributes.merge(auth: Base64.strict_encode64('a' * 15)))
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects endpoints containing credentials or insecure schemes' do
      register(attributes.merge(endpoint: 'https://user:pass@push.example.test/device'))
      expect(response).to have_http_status(:unprocessable_entity)
      register(attributes.merge(endpoint: 'http://push.example.test/device'))
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'preserves FCM registration' do
      post '/api/v1/notification_subscriptions', params: {
        notification_subscription: { subscription_type: 'fcm', subscription_attributes: { device_id: 'phone', push_token: 'fcm-token' } }
      }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(user.notification_subscriptions.fcm.last.subscription_attributes['push_token']).to eq('fcm-token')
    end
  end

  describe 'device diagnostics' do
    before do
      allow(VapidService).to receive(:public_key).and_return('test')
      allow(WebPush).to receive(:payload_send).and_return(true)
    end

    it 'sends only the authenticated user subscription and limits tests to three per minute' do
      create(:notification_subscription, :browser_push, user: user, identifier: endpoint, subscription_attributes: attributes)
      freeze_time do
        3.times do
          post '/api/v1/notification_subscriptions/test', params: { endpoint: endpoint }, headers: headers, as: :json
          expect(response).to have_http_status(:ok)
        end
        post '/api/v1/notification_subscriptions/test', params: { endpoint: endpoint }, headers: headers, as: :json
        expect(response).to have_http_status(:too_many_requests)
      end
      expect(WebPush).to have_received(:payload_send).exactly(3).times
    end

    it 'does not test another user device' do
      create(:notification_subscription, :browser_push, identifier: endpoint)
      post '/api/v1/notification_subscriptions/test', params: { endpoint: endpoint }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(WebPush).not_to have_received(:payload_send)
    end

    it 'rejects invalid diagnostic input' do
      post '/api/v1/notification_subscriptions/test', params: { endpoint: 'http://invalid.test' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'sanitizes delivery failures' do
      create(:notification_subscription, :browser_push, user: user, identifier: endpoint, subscription_attributes: attributes)
      allow(WebPush).to receive(:payload_send).and_raise(StandardError, 'private endpoint and token')
      post '/api/v1/notification_subscriptions/test', params: { endpoint: endpoint }, headers: headers, as: :json
      expect(response).to have_http_status(:bad_gateway)
      expect(response.body).not_to include('private endpoint')
    end

    it 'requires an authenticated session for diagnostics' do
      post '/api/v1/notification_subscriptions/test', params: { endpoint: endpoint }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'single read action' do
    let(:url) { "/api/v1/accounts/#{account.id}/notification_actions/#{notification.id}/read" }

    before { create(:inbox_member, user: user, inbox: conversation.inbox) }

    it 'marks only the indicated notice and is idempotent' do
      other = create(:notification, user: user, account: account, primary_actor: conversation, notification_type: 'conversation_mention')
      post url, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      read_at = notification.reload.read_at
      expect(read_at).to be_present
      post url, headers: headers, as: :json
      expect(notification.reload.read_at).to eq(read_at)
      expect(other.reload.read_at).to be_nil
    end

    it 'rejects a notice owned by another user' do
      notification.update!(user: create(:user, account: account))
      post url, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'rejects revoked conversation access without marking the notice' do
      notification
      InboxMember.where(inbox_id: conversation.inbox_id, user_id: user.id).destroy_all
      post url, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(notification.reload.read_at).to be_nil
    end

    it 'does not mark a notice from a different account' do
      notification.update!(account: create(:account))
      post url, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(notification.reload.read_at).to be_nil
    end
  end

  describe 'MFA enforcement' do
    before do
      skip('Skipping since MFA is not configured in this environment') unless Chatwoot.encryption_configured?
      account.update!(enforce_mfa: true)
    end

    it 'blocks diagnostics for non-enrolled API token users' do
      expect(WebPush).not_to receive(:payload_send)
      post '/api/v1/notification_subscriptions/test', params: { endpoint: endpoint },
                                                      headers: { api_access_token: user.access_token.token }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error_code']).to eq('mfa_enrollment_required')
    end

    it 'blocks notification actions for non-enrolled API token users' do
      post "/api/v1/accounts/#{account.id}/notification_actions/#{notification.id}/read",
           headers: { api_access_token: user.access_token.token }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error_code']).to eq('mfa_enrollment_required')
      expect(notification.reload.read_at).to be_nil
    end
  end

  it 'serves the worker overlay with a revalidation cache policy' do
    get '/notification-worker.js'
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/javascript')
    expect(response.headers['Cache-Control']).to eq('no-cache')
  end
end
