# frozen_string_literal: true

module Custom::Whatsapp::IncomingMessageIdentifierHelper
  def set_contact_from_message
    super
    enqueue_evolution_contact_enrichment if evolution_channel? && @contact.present?
  end

  def contact_attributes_from_contact_params(contact_params, source_identifier)
    attrs = super
    return attrs unless evolution_channel?

    enrich_evolution_contact_attributes!(attrs)
  end

  private

  def enrich_evolution_contact_attributes!(attrs)
    remote_jid = evolution_remote_jid_from_message
    return attrs if remote_jid.blank?

    attrs[:identifier] = remote_jid if remote_jid.end_with?('@lid')
    attrs[:additional_attributes] = (attrs[:additional_attributes] || {}).merge(
      Custom::Whatsapp::Evolution::ContactEnrichmentService::EVOLUTION_REMOTE_JID_KEY => remote_jid
    )
    attrs
  end

  def evolution_remote_jid_from_message
    message = messages_data&.first
    return if message.blank?

    message[:evolution_remote_jid].presence || message['evolution_remote_jid'].presence
  end

  def enqueue_evolution_contact_enrichment
    remote_jid = evolution_remote_jid_from_message
    push_name = @processed_params.dig(:contacts, 0, :profile, :name).to_s.strip.presence

    Custom::Whatsapp::Evolution::ContactEnrichmentJob.perform_later(
      inbox.channel.id,
      @contact.id,
      {
        remote_jid: remote_jid,
        push_name: push_name
      }.compact
    )
  end
end

Whatsapp::IncomingMessageIdentifierHelper.prepend_mod_with('Whatsapp::IncomingMessageIdentifierHelper')
