# frozen_string_literal: true

class Custom::Whatsapp::Evolution::GroupParticipantService
  pattr_initialize [:channel!, :participant_jid!, :push_name]

  def sync!
    return if participant_jid.blank?
    return if GroupContactService.group_jid?(participant_jid)

    phone = jid_resolver.phone_from_message_key({ 'remoteJid' => participant_jid })
    return if phone.blank?

    contact = channel.account.contacts.find_or_initialize_by(phone_number: "+#{phone}")
    contact.name = push_name.presence || contact.name || contact.phone_number
    contact.save!

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

  private

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::Evolution::JidResolver.new(channel.provider_config || {})
  end
end
