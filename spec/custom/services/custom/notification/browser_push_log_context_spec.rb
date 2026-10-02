require 'rails_helper'

RSpec.describe Custom::Notification::BrowserPushLogContext do
  let(:subscription) do
    build_stubbed(:notification_subscription, subscription_attributes: { endpoint: 'https://web.push.apple.com/private-device-token' })
  end

  it 'records provider and safe response fields without the endpoint or response content' do
    response = instance_double(Net::HTTPResponse, code: '403', body: { reason: 'BadJwtToken', token: 'sensitive-token' }.to_json)
    error = WebPush::Unauthorized.new(response, 'web.push.apple.com')
    context = described_class.build(user_id: subscription.user_id, subscription: subscription, error: error)
    expect(context).to include('provider=apple', 'result=failed', 'http_status=403', 'provider_reason=BadJwtToken',
                               'error_class=WebPush::Unauthorized')
    expect(context).not_to include('private-device-token', 'sensitive-token', 'https://')
  end

  it 'does not log arbitrary provider messages, unexpected JSON shapes or non-JSON responses' do
    ['null', '[]', '"sensitive-token"', 'not JSON', { reason: 'private-device-token' }.to_json].each do |body|
      response = instance_double(Net::HTTPResponse, code: '403', body: body)
      error = WebPush::Unauthorized.new(response, 'web.push.apple.com')
      context = described_class.build(user_id: subscription.user_id, subscription: subscription, error: error)
      expect(context).to include('http_status=403')
      expect(context).not_to include('provider_reason=', 'private-device-token', 'sensitive-token')
    end
  end

  [
    ['fcm.googleapis.com', 'google'], ['wns2-bl2p.notify.windows.com', 'microsoft'],
    ['updates.push.services.mozilla.com', 'mozilla'], ['web.push.apple.com.attacker.test', 'other']
  ].each do |host, provider|
    it "classifies #{host} without printing the host" do
      subscription.subscription_attributes['endpoint'] = "https://#{host}/private-token"
      context = described_class.build(user_id: subscription.user_id, subscription: subscription)
      expect(context).to include("provider=#{provider}", 'result=accepted')
      expect(context).not_to include(host, 'private-token')
    end
  end
end
