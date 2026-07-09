# frozen_string_literal: true

# Sends WhatsApp composing/paused presence when an agent toggles typing in the
# dashboard for an Evolution (Node) inbox. Uses POST /chat/sendPresence — not
# /instance/setPresence (instance-wide available/unavailable).
#
# Evolution holds the HTTP request for `delay` ms then forces paused. Keep the
# composing delay short so Sidekiq is not blocked; Chatwoot re-fires typing_on
# while the agent continues typing.
class Custom::Whatsapp::Evolution::PresenceSyncService
  COMPOSING_DELAY_MS = 3_000
  PAUSED_DELAY_MS = 0

  pattr_initialize [:conversation!, :typing_on!]

  def perform
    return unless evolution_inbox?

    peer = presence_peer
    return if peer.blank?

    if typing_on
      api_client.send_presence(number: peer, presence: 'composing', delay: COMPOSING_DELAY_MS)
    else
      api_client.send_presence(number: peer, presence: 'paused', delay: PAUSED_DELAY_MS)
    end
  rescue StandardError => e
    Rails.logger.warn(
      "[EVOLUTION] presence sync failed conversation=#{conversation.id}: #{e.message}"
    )
  end

  private

  def evolution_inbox?
    conversation.inbox.channel.is_a?(Channel::Whatsapp) &&
      conversation.inbox.channel.provider == 'evolution'
  end

  def presence_peer
    phone = conversation.contact&.phone_number.to_s.gsub(/\D/, '')
    return phone if phone.present?

    source_id = conversation.contact_inbox&.source_id.to_s
    return source_id if source_id.include?('@')

    digits = source_id.gsub(/\D/, '')
    digits.presence
  end

  def api_client
    Custom::Whatsapp::Evolution::ApiClient.for_channel(conversation.inbox.channel)
  end
end
