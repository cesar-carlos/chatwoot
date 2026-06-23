# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ContactEnrichmentJob < ApplicationJob
  queue_as :low

  DEDUP_TTL = 10.minutes.to_i

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(channel_id, contact_id, attrs = {})
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution')
    contact = Contact.find_by(id: contact_id)
    return if channel.blank? || contact.blank?

    attrs = attrs.with_indifferent_access
    return unless enrichment_allowed?(contact, attrs)

    Custom::Whatsapp::Evolution::ContactEnrichmentService.new(
      channel: channel,
      contact: contact,
      remote_jid: attrs[:remote_jid],
      push_name: attrs[:push_name],
      profile_pic_url: attrs[:profile_pic_url],
      force: attrs[:force]
    ).perform
  end

  private

  def enrichment_allowed?(contact, attrs)
    return true if ActiveModel::Type::Boolean.new.cast(attrs[:force])

    dedup_key = format(Redis::RedisKeys::EVOLUTION_CONTACT_ENRICHMENT, contact_id: contact.id)
    return false unless ::Redis::Alfred.set(dedup_key, true, nx: true, ex: DEDUP_TTL)

    !recently_enriched?(contact)
  end

  def recently_enriched?(contact)
    !Custom::Whatsapp::Evolution::ContactEnrichmentService.enrichment_stale?(contact)
  end
end
