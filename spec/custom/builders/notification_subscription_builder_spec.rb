require 'rails_helper'

RSpec.describe NotificationSubscriptionBuilder do
  let(:user) { create(:user) }
  let(:attributes) { { endpoint: 'https://push.example.test/device', p256dh: 'key', auth: 'auth' } }

  def register(target = user, endpoint: attributes[:endpoint])
    described_class.new(
      user: target,
      params: ActionController::Parameters.new(
        subscription_type: 'browser_push',
        subscription_attributes: attributes.merge(endpoint: endpoint)
      ).permit!
    ).perform
  end

  it 'records the device sync time when a browser subscription is created and refreshed' do
    created = travel_to(Time.zone.parse('2026-10-24 12:00:00')) { register }
    expect(created.last_synced_at).to be_within(1.second).of(Time.zone.parse('2026-10-24 12:00:00'))

    refreshed = travel_to(Time.zone.parse('2026-10-24 13:00:00')) { register }
    expect(refreshed.id).to eq(created.id)
    expect(refreshed.last_synced_at).to be_within(1.second).of(Time.zone.parse('2026-10-24 13:00:00'))
  end
end
