# frozen_string_literal: true

# Saves the WhatsApp id on the agent message before the echo webhook can insert
# a second outgoing row for the same source_id.
class Custom::Whatsapp::EvolutionGo::OutboundSourceClaim
  SECONDARY_SOURCE_IDS_KEY = 'evolution_go_secondary_source_ids'

  def self.claim!(message, source_id)
    new(message, source_id).claim!
  end

  def self.secondary?(inbox, source_id)
    return false if inbox.blank? || source_id.blank?

    # content_attributes is json plus a JSON store coder, so the column can hold a
    # stringified object. #>> '{}' unwraps that layer before the containment check.
    inbox.messages.exists?(
      ["(content_attributes #>> '{}')::jsonb @> ?", { SECONDARY_SOURCE_IDS_KEY => [source_id] }.to_json]
    )
  end

  def initialize(message, source_id)
    @message = message
    @source_id = source_id
    @lock = nil
    @acquired = false
  end

  def claim!
    return unless claimable?

    @lock = Custom::Whatsapp::EvolutionGo::MessageDedupLock.build(inbox: message.inbox, source_id: source_id)
    @acquired = @lock.acquire!
    unless @acquired
      Rails.logger.info(
        "[EVOLUTION_GO] outbound source claim deferred source_id=#{source_id} message=#{message.id}: dedup lock busy"
      )
      return
    end
    return if source_taken?

    message.update!(source_id: source_id)
  rescue StandardError => e
    Rails.logger.warn(
      "[EVOLUTION_GO] failed to claim outbound source_id=#{source_id} message=#{message&.id}: #{e.message}"
    )
  ensure
    release_lock!
  end

  private

  attr_reader :message, :source_id

  def claimable?
    message.present? && message.source_id.blank? && message.inbox.present?
  end

  def source_taken?
    message.class.exists?(inbox_id: message.inbox_id, source_id: source_id)
  end

  def release_lock!
    return unless @acquired && @lock

    @lock.release!
  end
end
