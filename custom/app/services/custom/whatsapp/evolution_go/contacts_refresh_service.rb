# frozen_string_literal: true

# Enqueues paced contact enrichment for every contact linked to an Evolution Go
# inbox. Used by the inbox settings "Refresh contact profiles" action.
#
# Strategy (aligned with WhatsApp usync rate limits):
# - Stagger Sidekiq jobs (ENQUEUE_SPACING) so workers do not burst /user/info+/user/avatar
# - Global enrichment concurrency remains capped at 3 (ContactEnrichmentConcurrency)
# - Lock TTL tracks paced ETA + buffer; a release job clears the lock when work should be done
class Custom::Whatsapp::EvolutionGo::ContactsRefreshService
  BATCH_SIZE = 100
  # Delay between each enqueued job. Keeps the :low queue from stampeding Go/WhatsApp.
  ENQUEUE_SPACING = 3.seconds
  # Extra time after the last paced job starts (runtime + queue delay).
  LOCK_TTL_BUFFER = 2.minutes.to_i
  # Ceiling only if the release job never runs. The TTL itself follows the paced ETA,
  # so a large inbox does not unlock while jobs are still queued (the old 3h cap did).
  LOCK_TTL_MAX = 24.hours.to_i

  class AlreadyRunningError < StandardError; end

  def self.lock_key_for(channel_id)
    format(Redis::RedisKeys::EVOLUTION_GO_CONTACTS_REFRESH_LOCK, channel_id: channel_id)
  end

  # Blank token is a no-op so an older release job cannot clear a newer refresh.
  def self.release_lock!(channel_id, refresh_token = nil)
    return if refresh_token.blank?

    ::Redis::Alfred.delete_if_equals(lock_key_for(channel_id), refresh_token.to_s)
  end

  def self.lock_status(channel)
    key = lock_key_for(channel.id)
    running = ::Redis::Alfred.get(key).present?
    ttl = ::Redis::Alfred.ttl(key).to_i
    {
      running: running,
      remaining_seconds: running && ttl.positive? ? ttl : 0
    }
  end

  pattr_initialize [:channel!]

  def perform
    contact_ids = inbox_contact_ids
    return empty_result if contact_ids.empty?

    raise AlreadyRunningError, 'Contact profile refresh already running' unless acquire_lock!(contact_ids.size)

    enqueued = enqueue_enrichments!(contact_ids)
    eta = (enqueued * ENQUEUE_SPACING).to_i
    schedule_lock_release!(eta)

    {
      enqueued: enqueued,
      spacing_seconds: ENQUEUE_SPACING.to_i,
      eta_seconds: eta,
      running: true,
      remaining_seconds: lock_ttl_for(enqueued)
    }
  rescue AlreadyRunningError
    raise
  rescue StandardError
    release_lock!
    raise
  end

  private

  def empty_result
    {
      enqueued: 0,
      spacing_seconds: ENQUEUE_SPACING.to_i,
      eta_seconds: 0,
      running: false,
      remaining_seconds: 0
    }
  end

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
    @refresh_token = SecureRandom.hex(16)
    ::Redis::Alfred.set(lock_key, @refresh_token, nx: true, ex: lock_ttl_for(contact_count))
  end

  def lock_ttl_for(contact_count)
    paced = (contact_count.to_i * ENQUEUE_SPACING.to_i) + LOCK_TTL_BUFFER
    paced.clamp(LOCK_TTL_BUFFER, LOCK_TTL_MAX)
  end

  def schedule_lock_release!(eta_seconds)
    wait = eta_seconds + LOCK_TTL_BUFFER
    Custom::Whatsapp::EvolutionGo::ContactsRefreshLockReleaseJob
      .set(wait: wait.seconds)
      .perform_later(channel.id, @refresh_token)
  end

  def release_lock!
    self.class.release_lock!(channel.id, @refresh_token)
  end

  def lock_key
    self.class.lock_key_for(channel.id)
  end
end
