class Custom::Notification::BulkReadService
  def self.perform(user:, account:, conversation: nil)
    scope = user.notifications.where(account_id: account.id, read_at: nil)
    scope = scope.where(primary_actor: conversation) if conversation
    cutoff = scope.maximum(:id)
    return unless cutoff

    read_at = Time.current
    # A bounded update preserves notifications inserted while this operation is in progress.
    scope.where(id: ..cutoff).update_all(read_at: read_at) # rubocop:disable Rails/SkipsModelValidations
    data = { account_id: account.id, user_id: user.id, through_notification_id: cutoff, read_at: read_at }
    data[:conversation_display_id] = conversation.display_id if conversation
    ActionCableBroadcastJob.perform_later([user.pubsub_token], 'notifications.read', data)
    data
  end
end
