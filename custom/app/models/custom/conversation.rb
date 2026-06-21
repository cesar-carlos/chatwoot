module Custom::Conversation
  private

  def execute_after_update_commit_callbacks
    super
    reset_first_reply_timestamp_on_single_history_reopen
  end

  def single_history_reopen_enabled?
    return true if inbox.lock_to_single_conversation?
    return false unless inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'evolution'

    (inbox.channel.provider_config || {}).fetch('reopen_conversation', true) != false
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
