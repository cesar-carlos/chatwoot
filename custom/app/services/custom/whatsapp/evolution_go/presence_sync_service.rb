# frozen_string_literal: true

# Sends WhatsApp composing/paused presence when an agent toggles typing in the
# dashboard for an Evolution Go inbox. Failures are logged and never raised —
# typing UX in Chatwoot must not depend on the Go round-trip.
class Custom::Whatsapp::EvolutionGo::PresenceSyncService
  pattr_initialize [:conversation!, :typing_on!]

  def perform
    return unless evolution_go_inbox?

    peer = presence_peer
    return if peer.blank?

    api_client.set_presence(
      number: peer,
      state: typing_on ? 'composing' : 'paused'
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[EVOLUTION_GO] presence sync failed conversation=#{conversation.id}: #{e.message}"
    )
  end

  private

  def evolution_go_inbox?
    conversation.inbox.channel.is_a?(Channel::Whatsapp) &&
      conversation.inbox.channel.provider == 'evolution_go'
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
    Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(conversation.inbox.channel)
  end
end
