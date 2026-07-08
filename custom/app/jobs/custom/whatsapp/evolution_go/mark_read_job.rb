# frozen_string_literal: true

# Runs the WhatsApp "mark as read" call outside the SendReplyJob (:high) so a
# slow /message/markread round-trip never delays the outgoing message itself.
class Custom::Whatsapp::EvolutionGo::MarkReadJob < ApplicationJob
  queue_as :default

  def perform(channel_id, phone_number, source_ids)
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution_go')
    return if channel.blank? || phone_number.blank? || source_ids.blank?

    Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel).mark_messages_read(
      number: phone_number, ids: Array.wrap(source_ids)
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION_GO] mark read on reply failed channel=#{channel_id}: #{e.message}"
  end
end
