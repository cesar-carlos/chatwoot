require 'rails_helper'

RSpec.describe Custom::Notification::PruneStaleSubscriptionsJob do
  let(:user) { create(:user) }

  def browser_subscription(created_at:, last_synced_at: nil, last_push_at: nil, last_push_status: nil, endpoint: "https://push.example.test/#{SecureRandom.hex(4)}")
    create(
      :notification_subscription,
      :browser_push,
      user: user,
      identifier: endpoint,
      subscription_attributes: { endpoint: endpoint },
      created_at: created_at,
      updated_at: created_at,
      last_synced_at: last_synced_at,
      last_push_at: last_push_at,
      last_push_status: last_push_status
    )
  end

  it 'removes stale browser subscriptions that have not received an accepted push' do
    stale = browser_subscription(created_at: 61.days.ago)
    synced = browser_subscription(created_at: 90.days.ago, last_synced_at: 1.day.ago)
    delivered = browser_subscription(
      created_at: 90.days.ago,
      last_synced_at: 90.days.ago,
      last_push_at: 1.day.ago,
      last_push_status: 'accepted'
    )
    old_delivery = browser_subscription(
      created_at: 90.days.ago,
      last_push_at: 61.days.ago,
      last_push_status: 'accepted'
    )
    failed = browser_subscription(
      created_at: 90.days.ago,
      last_synced_at: 90.days.ago,
      last_push_at: 1.day.ago,
      last_push_status: 'failed'
    )
    fcm = create(:notification_subscription, :fcm, user: user, identifier: 'phone', created_at: 90.days.ago, updated_at: 90.days.ago)

    allow(Rails.logger).to receive(:info)
    described_class.perform_now
    expect(Rails.logger).to have_received(:info).with('Pruned stale browser push subscriptions count=3')

    expect(NotificationSubscription.where(id: [stale.id, old_delivery.id, failed.id])).to be_empty
    expect(NotificationSubscription.where(id: [synced.id, delivered.id, fcm.id]).count).to eq(3)
  end
end
