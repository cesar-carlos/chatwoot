module Custom::Conversation
  private

  def execute_after_update_commit_callbacks
    super
    reset_first_reply_timestamp_on_single_history_reopen
  end

  def single_history_reopen_enabled?
    inbox.lock_to_single_conversation?
  end

  def reset_first_reply_timestamp_on_single_history_reopen
    return unless saved_change_to_status?
    return unless status_previously_was == 'resolved'
    return unless open? || pending?
    return unless single_history_reopen_enabled?

    # rubocop:disable Rails/SkipsModelValidations
    update_column(:first_reply_created_at, nil)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
