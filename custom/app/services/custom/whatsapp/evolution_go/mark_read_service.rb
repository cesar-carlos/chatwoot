# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::MarkReadService
  pattr_initialize [:conversation!]

  def perform
    return unless evolution_go_inbox?
    return unless mark_read_on_open?

    peer = mark_read_peer
    return if peer.blank?

    ids = unread_incoming_source_ids
    return if ids.blank?

    api_client.mark_messages_read(number: peer, ids: ids)
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION_GO] mark read on open failed conversation=#{conversation.id}: #{e.message}"
  end

  private

  def evolution_go_inbox?
    conversation.inbox.channel.is_a?(Channel::Whatsapp) &&
      conversation.inbox.channel.provider == 'evolution_go'
  end

  def mark_read_on_open?
    config = conversation.inbox.channel.provider_config || {}
    ActiveModel::Type::Boolean.new.cast(config['mark_read_on_open'])
  end

  # Prefer @lid / stored remote JID (WITHOUT-9 PN) over phone/source_id WITH-9.
  def mark_read_peer
    Custom::Whatsapp::EvolutionGo::ChatJid.for_conversation(conversation).presence ||
      fallback_peer_from_source_id
  end

  def fallback_peer_from_source_id
    source_id = conversation.contact_inbox&.source_id.to_s
    return source_id if source_id.include?('@')

    digits = source_id.gsub(/\D/, '')
    digits.presence || conversation.contact&.phone_number.to_s.gsub(/\D/, '').presence
  end

  def unread_incoming_source_ids
    conversation.messages
                .incoming
                .where.not(source_id: [nil, ''])
                .where.not(status: Message.statuses[:read])
                .order(created_at: :asc)
                .limit(20)
                .pluck(:source_id)
  end

  def api_client
    Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(conversation.inbox.channel)
  end
end
