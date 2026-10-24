# frozen_string_literal: true

class Custom::Notification::PruneStaleSubscriptionsJob < ApplicationJob
  queue_as :housekeeping

  STALE_AFTER = 60.days

  def perform
    cutoff = STALE_AFTER.ago
    removed = 0
    stale_browser_subscriptions(cutoff).find_each do |subscription|
      subscription.destroy!
      removed += 1
    end
    Rails.logger.info("Pruned stale browser push subscriptions count=#{removed}")
  end

  private

  def stale_browser_subscriptions(cutoff)
    NotificationSubscription.browser_push.where(
      'COALESCE(last_synced_at, created_at) < ?', cutoff
    ).where(
      "last_push_status IS DISTINCT FROM 'accepted' OR last_push_at IS NULL OR last_push_at < ?",
      cutoff
    )
  end
end
