# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength -- group + LID identity resolution for Evolution inbound
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

    return find_or_create_lid_contact_inbox! if whatsapp_lid_inbound?

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
    return attrs unless evolution_gateway_channel?

    enrich_evolution_contact_attributes!(attrs)
  end

  def set_contact_from_message
    if whatsapp_group_inbound?
      set_contact_from_group_message
      return
    end

    if whatsapp_lid_inbound?
      set_contact_from_lid_message
      return
    end

    super
    return if @contact.blank?

    enqueue_evolution_contact_enrichment if evolution_channel?
    enqueue_evolution_go_contact_enrichment if evolution_go_channel?
  end

  def set_contact_from_group_message
    contact_params = @processed_params[:contacts]&.first || {}
    attrs = contact_attributes_from_contact_params(contact_params, remote_jid_from_message)
    @contact_inbox = find_or_create_contact_inbox(
      source_ids: [remote_jid_from_message].compact,
      contact_attributes: attrs
    )
    @contact = @contact_inbox&.contact
  end

  def set_contact_from_lid_message
    @contact_inbox = find_or_create_lid_contact_inbox!
    @contact = @contact_inbox&.contact
    return if @contact.blank?

    enqueue_evolution_go_contact_enrichment
  end

  private

  def evolution_channel?
    inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'evolution'
  end

  def evolution_go_channel?
    inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'evolution_go'
  end

  def evolution_gateway_channel?
    evolution_channel? || evolution_go_channel?
  end

  def whatsapp_group_inbound?
    evolution_gateway_channel? &&
      Custom::Whatsapp::Evolution::GroupContactService.group_jid?(remote_jid_from_message)
  end

  def whatsapp_lid_inbound?
    evolution_go_channel? &&
      !whatsapp_group_inbound? &&
      remote_jid_from_message.to_s.end_with?('@lid')
  end

  def find_or_create_lid_contact_inbox!
    Custom::Whatsapp::EvolutionGo::PeerContactInboxResolver.new(
      channel: inbox.channel,
      key: lid_inbound_key
    ).find_or_create!
  end

  def lid_inbound_key
    addressing = remote_jid_from_message
    from = messages_data&.first&.with_indifferent_access&.[](:from).to_s
    alt = phone_alt_jid_from_wa_id(from)
    {
      'remoteJid' => addressing,
      'remoteJidAlt' => alt,
      'addressingMode' => 'lid',
      'fromMe' => false
    }.compact
  end

  def phone_alt_jid_from_wa_id(from)
    return if from.blank? || from.end_with?('@lid')
    return unless from.match?(/\A\d+\z/)

    "#{from}@s.whatsapp.net"
  end

  def whatsapp_group_provider?
    evolution_gateway_channel?
  end

  def enrich_evolution_contact_attributes!(attrs)
    remote_jid = remote_jid_from_message
    return attrs if remote_jid.blank?

    attrs[:identifier] = remote_jid if remote_jid.end_with?('@lid')
    jid_key = if evolution_go_channel?
                Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY
              else
                Custom::Whatsapp::Evolution::ContactEnrichmentService::EVOLUTION_REMOTE_JID_KEY
              end
    attrs[:additional_attributes] = (attrs[:additional_attributes] || {}).merge(jid_key => remote_jid)
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

    push_name = participant_push_name_from_message
    Custom::Whatsapp::Evolution::GroupParticipantService.new(
      channel: inbox.channel,
      participant_jid: participant_jid,
      push_name: push_name
    ).sync!
  end

  def participant_push_name_from_message
    message = messages_data&.first
    return if message.blank?

    message[:evolution_go_participant_push_name].presence ||
      message['evolution_go_participant_push_name'].presence ||
      message[:evolution_participant_push_name].presence ||
      message['evolution_participant_push_name'].presence
  end

  def enqueue_evolution_contact_enrichment
    remote_jid = remote_jid_from_message
    push_name = contact_push_name
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

  def enqueue_evolution_go_contact_enrichment
    remote_jid = remote_jid_from_message
    push_name = contact_push_name
    return unless Custom::Whatsapp::EvolutionGo::ContactEnrichmentService.should_enqueue?(
      contact: @contact,
      remote_jid: remote_jid,
      push_name: push_name
    )

    Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob.perform_later(
      inbox.channel.id,
      @contact.id,
      {
        remote_jid: remote_jid,
        push_name: push_name
      }.compact
    )
  end

  def contact_push_name
    @processed_params.dig(:contacts, 0, :profile, :name).to_s.strip.presence
  end
end
# rubocop:enable Metrics/ModuleLength

Whatsapp::IncomingMessageIdentifierHelper.prepend_mod_with('Whatsapp::IncomingMessageIdentifierHelper')
