require 'rails_helper'

RSpec.describe Notification::PushNotificationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:notification) { create(:notification, user: user, account: account) }
  let(:subscription) { create(:notification_subscription, :browser_push, user: user) }
  let(:service) { described_class.new(notification: notification) }

  before do
    allow(VapidService).to receive(:public_key).and_return('public-key')
    allow(VapidService).to receive(:private_key).and_return('private-key')
    allow(service).to receive(:push_message).and_return(title: 'New message', body: 'Hello', url: '/app/accounts/1/conversations/1')
  end

  it 'records an accepted browser push without touching updated_at' do
    updated_at = subscription.updated_at
    allow(WebPush).to receive(:payload_send).and_return(true)
    service.send(:send_browser_push, subscription)
    expect(subscription.reload).to have_attributes(last_push_status: 'accepted', last_push_error: nil)
    expect(subscription.updated_at).to be_within(1.second).of(updated_at)
  end

  it 'preserves browser subscriptions after an Apple authentication error and records its safe reason' do
    response = instance_double(Net::HTTPResponse, code: '403', body: { reason: 'BadJwtToken' }.to_json)
    allow(WebPush).to receive(:payload_send).and_raise(WebPush::Unauthorized.new(response, 'web.push.apple.com'))
    allow(Rails.logger).to receive(:error)
    service.send(:send_browser_push, subscription)
    expect(subscription.reload).to be_persisted
    expect(subscription.last_push_status).to eq('failed')
    expect(subscription.last_push_error).to eq('error_class=WebPush::Unauthorized http_status=403 provider_reason=BadJwtToken')
    expect(subscription.last_push_error).not_to include(subscription.identifier)
    expect(Rails.logger).to have_received(:error).with(include('http_status=403', 'provider_reason=BadJwtToken'))
  end

  [WebPush::InvalidSubscription, WebPush::ExpiredSubscription].each do |error_class|
    it "still removes an invalid or expired subscription (#{error_class})" do
      response = instance_double(Net::HTTPResponse, code: '410', body: '{}')
      allow(WebPush).to receive(:payload_send).and_raise(error_class.new(response, 'web.push.apple.com'))
      expect(Custom::Notification::PushDeliveryRecorder).to receive(:record)
        .with(subscription, status: 'expired', error: kind_of(error_class))
        .and_call_original
      service.send(:send_browser_push, subscription)
      expect { subscription.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it 'records rate limit and network failures without removing the subscription' do
    [
      WebPush::TooManyRequests.new(instance_double(Net::HTTPResponse, code: '429', body: '{}'), 'web.push.apple.com'),
      Net::OpenTimeout.new('execution expired')
    ].each do |error|
      subscription.update!(last_push_status: nil, last_push_error: nil)
      allow(WebPush).to receive(:payload_send).and_raise(error)
      service.send(:send_browser_push, subscription)
      expect(subscription.reload).to be_persisted
      expect(subscription.last_push_status).to eq('failed')
      expect(subscription.last_push_error).to include("error_class=#{error.class.name}")
      expect(subscription.last_push_error).not_to include(subscription.identifier)
    end
  end

  it 'sends a bounded payload for a long message while preserving routing' do
    allow(service).to receive(:push_message).and_return(title: 'New message', body: 'x' * 10_000, url: '/app/accounts/1/conversations/1')
    allow(WebPush).to receive(:payload_send).and_return(true)
    service.send(:send_browser_push, subscription)
    expect(WebPush).to have_received(:payload_send) do |payload|
      expect(payload[:message].bytesize).to be <= Custom::Notification::BrowserPushPayload::MAX_JSON_BYTES
      expect(JSON.parse(payload[:message])['url']).to eq('/app/accounts/1/conversations/1')
      expect(payload).to include(ttl: 1.day.to_i, urgency: 'high')
    end
  end
end
