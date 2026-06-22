# frozen_string_literal: true

class Custom::Whatsapp::Evolution::DeferredStatusJob < ApplicationJob
  queue_as :low

  retry_on StandardError, wait: 5.seconds, attempts: 6

  def perform(inbox_id, status_params)
    inbox = Inbox.find_by(id: inbox_id)
    return if inbox.blank?

    status = status_params.with_indifferent_access
    Whatsapp::IncomingMessageService.new(
      inbox: inbox,
      params: { statuses: [status] }
    ).perform
  end
end
