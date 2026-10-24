# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::MarkReadService
  # /message/markread accepts a list; keep batches small and move them off the
  # conversation request. Cap the backlog so one open cannot enqueue unbounded work.
  READ_BATCH_SIZE = 20
  MAX_UNREAD_IDS = 100

  pattr_initialize [:conversation!]

  def perform
    return unless evolution_go_inbox?
    return unless mark_read_on_open?

    peer = mark_read_peer
    return if peer.blank?

    ids = capped_unread_ids
    return if ids.blank?

    Custom::Whatsapp::EvolutionGo::MarkReadJob.perform_later(
      conversation.inbox.channel.id,
      peer,
      ids
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION_GO] mark read on open failed conversation=#{conversation.id}: #{e.message}"
  end

  private

  def evolution_go_inbox?
    conversation.inbox.channel.is_a?(Channel::Whatsapp) &&
      conversation.inbox.channel.provider == 'evolution_go'
  end

  def mark_read_on_open?
    Custom::Whatsapp::EvolutionGo::ProviderConfig.enabled?(
      conversation.inbox.channel.provider_config, 'mark_read_on_open'
    )
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

  def capped_unread_ids
    ids = unread_incoming_source_ids
    return ids if ids.size <= MAX_UNREAD_IDS

    Rails.logger.warn(
      "[EVOLUTION_GO] mark read on open truncated conversation=#{conversation.id} " \
      "count=#{ids.size} kept=#{MAX_UNREAD_IDS}"
    )
    ids.first(MAX_UNREAD_IDS)
  end

  def unread_incoming_source_ids
    conversation.messages
                .incoming
                .where.not(source_id: [nil, ''])
                .where.not(status: Message.statuses[:read])
                .order(created_at: :asc)
                .pluck(:source_id)
  end
end
