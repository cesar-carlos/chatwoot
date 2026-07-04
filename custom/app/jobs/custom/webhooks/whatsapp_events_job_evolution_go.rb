# frozen_string_literal: true

module Custom::Webhooks::WhatsappEventsJobEvolutionGo
  def perform(params = {})
    params = params.with_indifferent_access
    return super(params) unless evolution_go_envelope?(params)

    channel = find_evolution_go_channel(params)
    unless channel
      Rails.logger.warn("[EVOLUTION_GO] unknown channel_id=#{params[:channel_id]} instance=#{params[:evolution_go_instance_name]}")
      return super(params)
    end

    if channel_is_inactive?(channel)
      Rails.logger.warn("[EVOLUTION_GO] inactive channel instance=#{params[:evolution_go_instance_name]}")
      return
    end

    dispatch_evolution_go_event(channel, params)
  end

  private

  def evolution_go_envelope?(params)
    params[:evolution_go_instance_name].present?
  end

  def find_evolution_go_channel(params)
    channel_id = params[:channel_id]
    Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution_go') if channel_id.present?
  end

  def dispatch_evolution_go_event(channel, params)
    case params[:event]
    when 'MESSAGE'
      normalized = Custom::Whatsapp::Webhooks::EvolutionGoNormalizer.new(channel, params).perform
      super(normalized.merge(phone_number: channel.phone_number)) if normalized.present?
    when 'READ_RECEIPT'
      normalized = Custom::Whatsapp::Webhooks::EvolutionGoReadReceiptNormalizer.new(channel, params).perform
      super(normalized) if normalized.present?
    when 'CONNECTION', 'QRCODE'
      Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel).handle_event(params)
    when 'SEND_MESSAGE'
      nil
    else
      Rails.logger.info("[EVOLUTION_GO] ignored event=#{params[:event]} channel=#{channel.id}")
    end
  end
end

Webhooks::WhatsappEventsJob.prepend(Custom::Webhooks::WhatsappEventsJobEvolutionGo)
