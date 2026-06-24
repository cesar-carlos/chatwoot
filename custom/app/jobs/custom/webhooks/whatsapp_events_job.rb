# frozen_string_literal: true

module Custom::Webhooks::WhatsappEventsJob
  def perform(params = {})
    params = params.with_indifferent_access
    return super(params) unless evolution_envelope?(params)

    params = params.merge(event: Custom::Whatsapp::Evolution::EventNames.normalize(params[:event]))

    channel = find_evolution_channel(params)
    unless channel
      Rails.logger.warn("[EVOLUTION] unknown instance=#{evolution_instance_name(params)}")
      return
    end

    if channel_is_inactive?(channel)
      Rails.logger.warn("[EVOLUTION] inactive channel instance=#{evolution_instance_name(params)}")
      return
    end

    Custom::Whatsapp::Evolution::WebhookDispatcher.new(job: self).dispatch(channel, params)
  end

  private

  def evolution_envelope?(params)
    params[:event].present? && evolution_instance_name(params).present?
  end

  def evolution_instance_name(params)
    params[:instance_name].presence || params[:instance]
  end

  def find_evolution_channel(params)
    channel_id = params[:channel_id]
    return Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution') if channel_id.present?

    instance_name = evolution_instance_name(params)
    Channel::Whatsapp.where(provider: 'evolution')
                     .where("provider_config->>'instance_name' = ?", instance_name)
                     .first
  end
end

Webhooks::WhatsappEventsJob.prepend_mod_with('Webhooks::WhatsappEventsJob')
