# frozen_string_literal: true

module Custom::Whatsapp::IncomingMessageIdentifierHelper
  def find_or_create_contact_inbox(source_ids:, contact_attributes:)
    if whatsapp_group_inbound?
      contact_inbox = Custom::Whatsapp::Evolution::GroupContactService.new(
        channel: inbox.channel,
        remote_jid: remote_jid_from_message,
        push_name: contact_attributes[:name]
      ).find_or_create_contact_inbox!
      sync_group_participant!
      return contact_inbox
    end

    super
  end

  def contact_attributes_from_contact_params(contact_params, source_identifier)
    if whatsapp_group_inbound?
      return Custom::Whatsapp::Evolution::GroupContactService.new(
        channel: inbox.channel,
        remote_jid: remote_jid_from_message,
        push_name: contact_params.dig(:profile, :name)
      ).contact_attributes
    end

    attrs = super
    return attrs unless evolution_channel?

    enrich_evolution_contact_attributes!(attrs)
  end

  def set_contact_from_message
    super
    enqueue_evolution_contact_enrichment if evolution_channel? && @contact.present? && !whatsapp_group_inbound?
  end

  private

  def evolution_channel?
    inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'evolution'
  end

  def evolution_go_channel?
    inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'evolution_go'
  end

  def whatsapp_group_inbound?
    whatsapp_group_provider? &&
      Custom::Whatsapp::Evolution::GroupContactService.group_jid?(remote_jid_from_message)
  end

  def whatsapp_group_provider?
    evolution_channel? || evolution_go_channel?
  end

  def enrich_evolution_contact_attributes!(attrs)
    remote_jid = remote_jid_from_message
    return attrs if remote_jid.blank?

    attrs[:identifier] = remote_jid if remote_jid.end_with?('@lid')
    attrs[:additional_attributes] = (attrs[:additional_attributes] || {}).merge(
      Custom::Whatsapp::Evolution::ContactEnrichmentService::EVOLUTION_REMOTE_JID_KEY => remote_jid
    )
    attrs
  end

  def remote_jid_from_message
    message = messages_data&.first
    return if message.blank?

    message[:evolution_remote_jid].presence || message['evolution_remote_jid'].presence ||
      message[:evolution_go_remote_jid].presence || message['evolution_go_remote_jid'].presence
  end

  def participant_jid_from_message
    message = messages_data&.first
    return if message.blank?

    message[:evolution_participant_jid].presence || message['evolution_participant_jid'].presence ||
      message[:evolution_go_participant_jid].presence || message['evolution_go_participant_jid'].presence
  end

  def sync_group_participant!
    participant_jid = participant_jid_from_message
    return if participant_jid.blank?

    push_name = @processed_params.dig(:contacts, 0, :profile, :name).to_s.strip.presence
    Custom::Whatsapp::Evolution::GroupParticipantService.new(
      channel: inbox.channel,
      participant_jid: participant_jid,
      push_name: push_name
    ).sync!
  end

  def enqueue_evolution_contact_enrichment
    remote_jid = remote_jid_from_message
    push_name = @processed_params.dig(:contacts, 0, :profile, :name).to_s.strip.presence
    return unless Custom::Whatsapp::Evolution::ContactEnrichmentService.should_enqueue?(
      contact: @contact,
      remote_jid: remote_jid,
      push_name: push_name
    )

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
