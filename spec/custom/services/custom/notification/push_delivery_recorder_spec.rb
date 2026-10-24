require 'rails_helper'

RSpec.describe Custom::Notification::PushDeliveryRecorder do
  let(:subscription) do
    create(
      :notification_subscription,
      :browser_push,
      identifier: 'https://push.example.test/private-device',
      subscription_attributes: { endpoint: 'https://push.example.test/private-device' }
    )
  end

  it 'stores each delivery result without changing updated_at or recording secrets' do
    updated_at = subscription.updated_at
    response = instance_double(
      Net::HTTPResponse,
      code: '403',
      body: { reason: 'BadJwtToken', endpoint: subscription.identifier }.to_json
    )
    error = WebPush::Unauthorized.new(response, 'web.push.apple.com')

    described_class.record(subscription, status: 'failed', error: error)

    expect(subscription.reload).to have_attributes(
      last_push_status: 'failed',
      last_push_error: 'error_class=WebPush::Unauthorized http_status=403 provider_reason=BadJwtToken'
    )
    expect(subscription.last_push_at).to be_within(2.seconds).of(Time.current)
    expect(subscription.last_push_error).not_to include(subscription.identifier)
    expect(subscription.updated_at).to be_within(1.second).of(updated_at)
  end

  it 'clears the previous error when a later delivery is accepted' do
    subscription.update!(last_push_status: 'failed', last_push_error: 'error_class=StandardError')
    described_class.record(subscription, status: 'accepted')
    expect(subscription.reload).to have_attributes(last_push_status: 'accepted', last_push_error: nil)
  end
end
