# frozen_string_literal: true

class Custom::Whatsapp::Evolution::GroupParticipantService
  pattr_initialize [:channel!, :participant_jid!, :push_name]

  def sync!
    return if skip_participant_sync?

    contact = upsert_participant_contact!
    return if contact.blank?

    enqueue_enrichment_for(contact)
  end

  private

  def skip_participant_sync?
    participant_jid.blank? ||
      Custom::Whatsapp::Evolution::GroupContactService.group_jid?(participant_jid)
  end

  def upsert_participant_contact!
    phone = jid_resolver.phone_from_message_key({ 'remoteJid' => participant_jid })
    return if phone.blank?

    contact = channel.account.contacts.find_or_initialize_by(phone_number: "+#{phone}")
    contact.name = push_name.presence || contact.name || contact.phone_number
    contact.save!
    contact
  end

  def enqueue_enrichment_for(contact)
    return unless Custom::Whatsapp::Evolution::ContactEnrichmentService.should_enqueue?(
      contact: contact,
      remote_jid: participant_jid,
      push_name: push_name
    )

    Custom::Whatsapp::Evolution::ContactEnrichmentJob.perform_later(
      channel.id,
      contact.id,
      { remote_jid: participant_jid, push_name: push_name }.compact
    )
  end

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::Evolution::JidResolver.new(channel.provider_config || {})
  end
end
