require 'rails_helper'

RSpec.describe 'Custom notification subscription deletion', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }

  it 'removes a browser push subscription owned by the authenticated user' do
    subscription = create(
      :notification_subscription,
      :browser_push,
      user: agent,
      identifier: 'https://push.example.test/current-user',
      subscription_attributes: {
        endpoint: 'https://push.example.test/current-user',
        p256dh: 'p256dh',
        auth: 'auth'
      }
    )

    delete '/api/v1/notification_subscriptions',
           params: { endpoint: subscription.identifier },
           headers: headers,
           as: :json

    expect(response).to have_http_status(:ok)
    expect { subscription.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not remove a browser push subscription owned by another user' do
    other_user = create(:user, account: account, role: :agent)
    subscription = create(
      :notification_subscription,
      :browser_push,
      user: other_user,
      identifier: 'https://push.example.test/other-user',
      subscription_attributes: {
        endpoint: 'https://push.example.test/other-user',
        p256dh: 'p256dh',
        auth: 'auth'
      }
    )

    delete '/api/v1/notification_subscriptions',
           params: { endpoint: subscription.identifier },
           headers: headers,
           as: :json

    expect(response).to have_http_status(:ok)
    expect { subscription.reload }.not_to raise_error
  end

  it 'preserves FCM removal by push token' do
    subscription = create(
      :notification_subscription,
      :fcm,
      user: agent,
      identifier: 'fcm-device',
      subscription_attributes: {
        device_id: 'fcm-device',
        push_token: 'fcm-token'
      }
    )

    delete '/api/v1/notification_subscriptions',
           params: { push_token: 'fcm-token' },
           headers: headers,
           as: :json

    expect(response).to have_http_status(:ok)
    expect { subscription.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
