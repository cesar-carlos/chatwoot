# frozen_string_literal: true

module Custom::Api::V1::Accounts::ContactsController
  # FORK: force Evolution Go contact profile + avatar sync from conversation menu
  def evolution_go_sync
    channel = resolve_evolution_go_channel_for_sync
    return render_evolution_go_sync_error('Evolution Go WhatsApp inbox not found for this contact') if channel.blank?
    return unless enqueue_evolution_go_sync!(channel)

    render json: { message: 'Contact sync started' }, status: :accepted
  end

  private

  def enqueue_evolution_go_sync!(channel)
    return enqueue_group_sync!(channel) if whatsapp_group_contact?

    enqueue_peer_sync!(channel)
    true
  end

  def enqueue_group_sync!(channel)
    group_jid = group_jid_for_sync
    if group_jid.blank?
      render_evolution_go_sync_error('WhatsApp group JID missing for this contact')
      return false
    end

    Custom::Whatsapp::Evolution::GroupMetadataFetchJob.perform_later(channel.id, group_jid)
    true
  end

  def enqueue_peer_sync!(channel)
    remote_jid = @contact.additional_attributes.to_h['evolution_go_remote_jid']
    Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob.perform_later(
      channel.id,
      @contact.id,
      remote_jid: remote_jid,
      force: true
    )
  end

  def render_evolution_go_sync_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def whatsapp_group_contact?
    attrs = @contact.additional_attributes.to_h.stringify_keys
    return true if ActiveModel::Type::Boolean.new.cast(
      attrs[Custom::Whatsapp::Evolution::GroupKeys::IS_WHATSAPP_GROUP_KEY]
    )

    group_jid_for_sync.present?
  end

  def group_jid_for_sync
    attrs = @contact.additional_attributes.to_h.stringify_keys
    [
      attrs[Custom::Whatsapp::Evolution::GroupKeys::EVOLUTION_GROUP_JID_KEY],
      @contact.identifier
    ].find { |value| Custom::Whatsapp::Evolution::GroupContactService.group_jid?(value) }.to_s.presence
  end

  def resolve_evolution_go_channel_for_sync
    channel_from_inbox_param || channel_from_contact_inboxes
  end

  def channel_from_inbox_param
    inbox_id = params[:inbox_id].presence
    return if inbox_id.blank?

    channel = Current.account.inboxes.find_by(id: inbox_id)&.channel
    channel if evolution_go_whatsapp_channel?(channel)
  end

  def channel_from_contact_inboxes
    @contact.contact_inboxes.includes(inbox: :channel).find do |ci|
      evolution_go_whatsapp_channel?(ci.inbox&.channel)
    end&.inbox&.channel
  end

  def evolution_go_whatsapp_channel?(channel)
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'
  end
end
