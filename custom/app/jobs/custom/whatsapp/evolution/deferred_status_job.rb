# frozen_string_literal: true

class Custom::Whatsapp::Evolution::DeferredStatusJob < ApplicationJob
  queue_as :low

  MAX_ATTEMPTS = 6
  DEFER_WAIT = 5.seconds

  retry_on StandardError, wait: DEFER_WAIT, attempts: MAX_ATTEMPTS do |job, error|
    Rails.logger.warn(
      "[EVOLUTION] deferred status dropped inbox=#{job.arguments.first} " \
      "message_id=#{job.arguments.second&.dig('id') || job.arguments.second&.dig(:id)}: #{error.message}"
    )
  end

  def perform(inbox_id, status_params, attempt = 1)
    inbox = Inbox.find_by(id: inbox_id)
    return if inbox.blank?

    status = status_params.with_indifferent_access
    return reschedule_or_drop(inbox_id, status_params, attempt, status[:id]) unless inbox.messages.exists?(source_id: status[:id])

    Whatsapp::IncomingMessageService.new(
      inbox: inbox,
      params: { statuses: [status] }
    ).perform
  end

  private

  def reschedule_or_drop(inbox_id, status_params, attempt, source_id)
    if attempt < MAX_ATTEMPTS
      self.class.set(wait: DEFER_WAIT).perform_later(inbox_id, status_params, attempt + 1)
      Rails.logger.info(
        "[EVOLUTION] status update deferred source_id=#{source_id} attempt=#{attempt}/#{MAX_ATTEMPTS}"
      )
      return
    end

    Rails.logger.warn(
      "[EVOLUTION] deferred status dropped inbox=#{inbox_id} message_id=#{source_id}: " \
      "message not found after #{MAX_ATTEMPTS} attempts"
    )
  end
end
