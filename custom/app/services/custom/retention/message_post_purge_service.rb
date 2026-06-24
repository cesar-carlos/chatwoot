class Custom::Retention::MessagePostPurgeService
  pattr_initialize [:message, :account!, :run_id!]

  def perform
    notify_update
    reindex_for_search
  end

  private

  def notify_update
    return if message.blank?
    return if message.content_attributes&.dig('deleted')

    message.reload.send_update_event
  rescue StandardError => e
    log('message_update_failed', message_id: message&.id, error: e.message)
  end

  def reindex_for_search
    return if message.blank?
    return unless message.should_index?

    message.reindex(mode: :async)
  rescue StandardError => e
    log('reindex_failed', message_id: message&.id, error: e.message)
  end

  def log(event, payload)
    Rails.logger.info(
      {
        component: 'Custom::Retention::MessagePostPurgeService',
        event: event,
        account_id: account.id,
        run_id: run_id,
        **payload
      }.to_json
    )
  end
end
