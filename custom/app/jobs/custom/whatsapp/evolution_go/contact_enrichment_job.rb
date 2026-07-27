# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob < ApplicationJob
  include Custom::Whatsapp::ContactEnrichmentConcurrency

  queue_as :low

  IN_FLIGHT_LOCK_TTL = 2.minutes.to_i
  FORCE_LOCK_RETRY_WAIT = 5.seconds
  FORCE_LOCK_RETRY_MAX = 3

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(channel_id, contact_id, attrs = {})
    @lock_acquired = false
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution_go')
    contact = Contact.find_by(id: contact_id)
    return if channel.blank? || contact.blank?

    attrs = attrs.with_indifferent_access
    return unless enrichment_allowed?(contact, attrs)
    return unless acquire_lock_or_requeue!(contact, attrs)

    @lock_acquired = true
    run_enrichment!(channel, contact, attrs)
  ensure
    release_in_flight_lock!(contact) if contact && @lock_acquired
  end

  private

  def run_enrichment!(channel, contact, attrs)
    with_global_enrichment_slot do
      Custom::Whatsapp::EvolutionGo::ContactEnrichmentService.new(
        channel: channel,
        contact: contact,
        remote_jid: attrs[:remote_jid],
        push_name: attrs[:push_name],
        force: attrs[:force]
      ).perform
    end
  end

  def acquire_lock_or_requeue!(contact, attrs)
    return true if acquire_in_flight_lock!(contact)

    # Force Sync: previous attempt still running (Go avatar timeouts are slow) —
    # requeue instead of silently dropping the click (capped).
    if ActiveModel::Type::Boolean.new.cast(attrs[:force])
      retry_attempt = attrs[:force_retry_attempt].to_i
      if retry_attempt < FORCE_LOCK_RETRY_MAX
        self.class.set(wait: FORCE_LOCK_RETRY_WAIT).perform_later(
          arguments.first,
          contact.id,
          attrs.merge(force_retry_attempt: retry_attempt + 1).to_h
        )
      end
    end
    false
  end

  def enrichment_allowed?(contact, attrs)
    Custom::Whatsapp::EvolutionGo::ContactEnrichmentService.should_enqueue?(
      contact: contact,
      remote_jid: attrs[:remote_jid],
      push_name: attrs[:push_name],
      force: attrs[:force]
    )
  end

  def acquire_in_flight_lock!(contact)
    ::Redis::Alfred.set(in_flight_lock_key(contact), true, nx: true, ex: IN_FLIGHT_LOCK_TTL)
  end

  def release_in_flight_lock!(contact)
    ::Redis::Alfred.delete(in_flight_lock_key(contact))
  end

  def in_flight_lock_key(contact)
    format(Redis::RedisKeys::EVOLUTION_GO_CONTACT_ENRICHMENT, contact_id: contact.id)
  end
end
