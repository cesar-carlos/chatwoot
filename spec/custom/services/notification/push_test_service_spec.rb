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
end
