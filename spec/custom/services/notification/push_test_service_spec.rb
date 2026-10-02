require 'rails_helper'

RSpec.describe Notification::PushTestService do
  let(:user) { create(:user) }
  let(:subscription) do
    create(
      :notification_subscription,
      :browser_push,
      user: user,
      identifier: 'https://push.example.test/device',
      subscription_attributes: {
        endpoint: 'https://push.example.test/device',
        p256dh: 'p256dh',
        auth: 'auth'
      }
    )
  end

  before do
    allow(VapidService).to receive(:public_key).and_return('public-key')
    allow(VapidService).to receive(:private_key).and_return('private-key')
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load)
      .with('PWA_ICON_URL', '/favicon-512x512.png')
      .and_return('/brand-assets/pwa-icon-se7e-512.png')
    allow(WebPush).to receive(:payload_send).and_return(true)
  end

  it 'uses the production browser payload shape and clarifies delivery semantics' do
    result = described_class.new(
      user: user,
      subscription_ids: [subscription.id],
      title: 'Diagnostic title',
      body: 'Diagnostic body'
    ).perform

    expect(WebPush).to have_received(:payload_send) do |payload|
      message = JSON.parse(payload[:message])
      expect(message).to include(
        'title' => 'Diagnostic title',
        'body' => 'Diagnostic body',
        'icon' => '/brand-assets/pwa-icon-se7e-512.png'
      )
      expect(payload).to include(ttl: 1.day.to_i, urgency: 'high')
    end
    expect(result.first).to include(
      status: :success,
      message: 'Accepted by push service; device display is not confirmed'
    )
  end

  it 'limits the diagnostic content using the same byte budget as real notifications' do
    described_class.new(user: user, subscription_ids: [subscription.id], title: 'Test', body: '😀' * 5000).perform
    expect(WebPush).to have_received(:payload_send) do |payload|
      expect(payload[:message].bytesize).to be <= Custom::Notification::BrowserPushPayload::MAX_JSON_BYTES
      expect(JSON.parse(payload[:message])['body']).to end_with('…')
    end
  end

  it 'preserves authentication failures and returns a sanitized delivery error' do
    response = instance_double(Net::HTTPResponse, code: '403', body: { reason: 'BadJwtToken', token: 'private-token' }.to_json)
    allow(WebPush).to receive(:payload_send).and_raise(WebPush::Unauthorized.new(response, 'web.push.apple.com'))
    result = described_class.new(user: user, subscription_ids: [subscription.id]).perform.first
    expect(subscription.reload).to be_persisted
    expect(result).to include(status: :failure, message: 'Push service did not accept the test notification')
    expect(result[:message]).not_to include('private-token')
  end

  it 'removes expired subscriptions detected by a diagnostic' do
    response = instance_double(Net::HTTPResponse, code: '410', body: '{}')
    allow(WebPush).to receive(:payload_send).and_raise(WebPush::ExpiredSubscription.new(response, 'web.push.apple.com'))
    result = described_class.new(user: user, subscription_ids: [subscription.id]).perform.first
    expect(result[:status]).to eq(:failure)
    expect { subscription.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
