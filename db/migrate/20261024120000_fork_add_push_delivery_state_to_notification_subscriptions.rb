# FORK: record browser push sync and delivery state for diagnostics and pruning
class ForkAddPushDeliveryStateToNotificationSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :notification_subscriptions, :last_synced_at, :datetime
    add_column :notification_subscriptions, :last_push_at, :datetime
    add_column :notification_subscriptions, :last_push_status, :string
    add_column :notification_subscriptions, :last_push_error, :string
  end
end
