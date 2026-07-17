# frozen_string_literal: true

# Enqueues forced contact enrichment for every contact linked to an Evolution
# inbox. Used by the inbox settings "Refresh contact profiles" action.
class Custom::Whatsapp::Evolution::ContactsRefreshService
  BATCH_SIZE = 100
  # Prevents double-click floods while jobs drain; release job clears earlier.
  LOCK_TTL = 10.minutes.to_i

  class AlreadyRunningError < StandardError; end

  def self.lock_key_for(channel_id)
    format(Redis::RedisKeys::EVOLUTION_CONTACTS_REFRESH_LOCK, channel_id: channel_id)
  end

  def self.release_lock!(channel_id)
    ::Redis::Alfred.delete(lock_key_for(channel_id))
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

    raise AlreadyRunningError, 'Contact profile refresh already running' unless acquire_lock!

    enqueue_enrichments!(contact_ids)
    schedule_lock_release!

    {
      enqueued: contact_ids.size,
      running: true,
      remaining_seconds: LOCK_TTL
    }
  rescue AlreadyRunningError
    raise
  rescue StandardError
    release_lock!
    raise
  end

  private

  def empty_result
    { enqueued: 0, running: false, remaining_seconds: 0 }
  end

  def inbox
    channel.inbox
  end

  def inbox_contact_ids
    ContactInbox.where(inbox_id: inbox.id).distinct.pluck(:contact_id)
  end

  def enqueue_enrichments!(contact_ids)
    contact_ids.each_slice(BATCH_SIZE) do |batch|
      Contact.where(id: batch).find_each do |contact|
        remote_jid = contact.additional_attributes.to_h[
          Custom::Whatsapp::Evolution::ContactEnrichmentService::EVOLUTION_REMOTE_JID_KEY
        ]
        Custom::Whatsapp::Evolution::ContactEnrichmentJob.perform_later(
          channel.id,
          contact.id,
          remote_jid: remote_jid,
          force: true
        )
      end
    end
  end

  def acquire_lock!
    ::Redis::Alfred.set(lock_key, true, nx: true, ex: LOCK_TTL)
  end

  def schedule_lock_release!
    Custom::Whatsapp::Evolution::ContactsRefreshLockReleaseJob
      .set(wait: LOCK_TTL.seconds)
      .perform_later(channel.id)
  end

  def release_lock!
    self.class.release_lock!(channel.id)
  end

  def lock_key
    self.class.lock_key_for(channel.id)
  end
end
