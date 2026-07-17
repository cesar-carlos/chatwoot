# frozen_string_literal: true

# Enqueues paced contact enrichment for every contact linked to an Evolution Go
# inbox. Used by the inbox settings "Refresh contact profiles" action.
#
# Strategy (aligned with WhatsApp usync rate limits):
# - Stagger Sidekiq jobs (ENQUEUE_SPACING) so workers do not burst /user/info+/user/avatar
# - Global enrichment concurrency remains capped at 3 (ContactEnrichmentConcurrency)
# - Lock TTL scales with contact count so a second click cannot double the flood
class Custom::Whatsapp::EvolutionGo::ContactsRefreshService
  BATCH_SIZE = 100
  # Delay between each enqueued job. Keeps the :low queue from stampeding Go/WhatsApp.
  ENQUEUE_SPACING = 3.seconds
  LOCK_TTL_BASE = 30.minutes.to_i
  LOCK_TTL_MAX = 3.hours.to_i

  class AlreadyRunningError < StandardError; end

  pattr_initialize [:channel!]

  def perform
    contact_ids = inbox_contact_ids
    raise AlreadyRunningError, 'Contact profile refresh already running' unless acquire_lock!(contact_ids.size)

    enqueued = enqueue_enrichments!(contact_ids)
    {
      enqueued: enqueued,
      spacing_seconds: ENQUEUE_SPACING.to_i,
      eta_seconds: (enqueued * ENQUEUE_SPACING).to_i
    }
  rescue AlreadyRunningError
    raise
  rescue StandardError
    release_lock!
    raise
  end

  private

  def inbox
    channel.inbox
  end

  def inbox_contact_ids
    ContactInbox.where(inbox_id: inbox.id).distinct.pluck(:contact_id)
  end

  def enqueue_enrichments!(contact_ids)
    enqueued = 0

    contact_ids.each_slice(BATCH_SIZE) do |batch|
      Contact.where(id: batch).find_each do |contact|
        remote_jid = contact.additional_attributes.to_h[
          Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY
        ]
        Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob
          .set(wait: enqueued * ENQUEUE_SPACING)
          .perform_later(
            channel.id,
            contact.id,
            remote_jid: remote_jid,
            force: true
          )
        enqueued += 1
      end
    end

    enqueued
  end

  def acquire_lock!(contact_count)
    ::Redis::Alfred.set(lock_key, true, nx: true, ex: lock_ttl_for(contact_count))
  end

  def lock_ttl_for(contact_count)
    paced = LOCK_TTL_BASE + (contact_count.to_i * ENQUEUE_SPACING.to_i)
    [paced, LOCK_TTL_MAX].min
  end

  def release_lock!
    ::Redis::Alfred.delete(lock_key)
  end

  def lock_key
    format(Redis::RedisKeys::EVOLUTION_GO_CONTACTS_REFRESH_LOCK, channel_id: channel.id)
  end
end
