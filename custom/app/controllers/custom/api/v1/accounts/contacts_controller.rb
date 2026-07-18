# frozen_string_literal: true

module Custom::Api::V1::Accounts::ContactsController
  # FORK: force Evolution Go contact profile + avatar sync from conversation menu
  def evolution_go_sync
    channel = resolve_evolution_go_channel_for_sync
    if channel.blank?
      return render json: { error: 'Evolution Go WhatsApp inbox not found for this contact' },
                    status: :unprocessable_entity
    end

    remote_jid = @contact.additional_attributes.to_h['evolution_go_remote_jid']
    Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob.perform_later(
      channel.id,
      @contact.id,
      remote_jid: remote_jid,
      force: true
    )

    render json: { message: 'Contact sync started' }, status: :accepted
  end

  private

  def resolve_evolution_go_channel_for_sync
    inbox_id = params[:inbox_id].presence
    if inbox_id.present?
      channel = Current.account.inboxes.find_by(id: inbox_id)&.channel
      return channel if evolution_go_whatsapp_channel?(channel)
    end

    @contact.contact_inboxes.includes(inbox: :channel).find do |ci|
      evolution_go_whatsapp_channel?(ci.inbox&.channel)
    end&.inbox&.channel
  end

  def evolution_go_whatsapp_channel?(channel)
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'
  end
end
