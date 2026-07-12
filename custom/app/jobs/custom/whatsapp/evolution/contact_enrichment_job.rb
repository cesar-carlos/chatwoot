# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ContactEnrichmentJob < ApplicationJob
  include Custom::Whatsapp::ContactEnrichmentConcurrency

  queue_as :low

  IN_FLIGHT_LOCK_TTL = 2.minutes.to_i

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(channel_id, contact_id, attrs = {})
    @lock_acquired = false
    channel, contact = load_enrichment_targets(channel_id, contact_id)
    return if channel.blank? || contact.blank?

    attrs = attrs.with_indifferent_access
    return unless enrichment_allowed?(contact, attrs)
    return unless acquire_in_flight_lock!(contact)

    @lock_acquired = true
    run_enrichment!(channel, contact, attrs)
  ensure
    release_in_flight_lock!(contact) if contact && @lock_acquired
  end

  private

  def load_enrichment_targets(channel_id, contact_id)
    [
      Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution'),
      Contact.find_by(id: contact_id)
    ]
  end

  def run_enrichment!(channel, contact, attrs)
    with_global_enrichment_slot do
      Custom::Whatsapp::Evolution::ContactEnrichmentService.new(
        channel: channel,
        contact: contact,
        remote_jid: attrs[:remote_jid],
        push_name: attrs[:push_name],
        profile_pic_url: attrs[:profile_pic_url],
        force: attrs[:force]
      ).perform
    end
  end

  def enrichment_allowed?(contact, attrs)
    return true if ActiveModel::Type::Boolean.new.cast(attrs[:force])
    return true if attrs[:profile_pic_url].present? && !contact.avatar.attached?

    !recently_enriched?(contact)
  end

  def recently_enriched?(contact)
    !Custom::Whatsapp::Evolution::ContactEnrichmentService.enrichment_stale?(contact)
  end

  def acquire_in_flight_lock!(contact)
    ::Redis::Alfred.set(in_flight_lock_key(contact), true, nx: true, ex: IN_FLIGHT_LOCK_TTL)
  end

  def release_in_flight_lock!(contact)
    ::Redis::Alfred.delete(in_flight_lock_key(contact))
  end

  def in_flight_lock_key(contact)
    format(Redis::RedisKeys::EVOLUTION_CONTACT_ENRICHMENT, contact_id: contact.id)
  end
end
