# frozen_string_literal: true

# Enqueues forced contact enrichment for every contact linked to an Evolution Go
# inbox. Used by the inbox settings "Refresh contact profiles" action.
class Custom::Whatsapp::EvolutionGo::ContactsRefreshService
  BATCH_SIZE = 100
  LOCK_TTL = 30.minutes.to_i

  class AlreadyRunningError < StandardError; end

  pattr_initialize [:channel!]

  def perform
    raise AlreadyRunningError, 'Contact profile refresh already running' unless acquire_lock!

    contact_ids = inbox_contact_ids
    enqueue_enrichments!(contact_ids)
    { enqueued: contact_ids.size }
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
    contact_ids.each_slice(BATCH_SIZE) do |batch|
      Contact.where(id: batch).find_each do |contact|
        remote_jid = contact.additional_attributes.to_h[
          Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY
        ]
        Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob.perform_later(
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

  def release_lock!
    ::Redis::Alfred.delete(lock_key)
  end

  def lock_key
    format(Redis::RedisKeys::EVOLUTION_GO_CONTACTS_REFRESH_LOCK, channel_id: channel.id)
  end
end
