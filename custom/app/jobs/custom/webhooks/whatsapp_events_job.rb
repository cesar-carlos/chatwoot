# frozen_string_literal: true

module Custom::Webhooks::WhatsappEventsJob
  EVOLUTION_MESSAGE_LOCK_TTL = 30.seconds

  def perform(params = {})
    params = params.with_indifferent_access
    return super(params) unless evolution_envelope?(params)

    channel = find_evolution_channel(params)
    unless channel
      Rails.logger.warn("[EVOLUTION] unknown instance=#{params[:instance]}")
      return
    end

    if channel_is_inactive?(channel)
      Rails.logger.warn("[EVOLUTION] inactive channel instance=#{params[:instance]}")
      return
    end

    case params[:event]
    when 'MESSAGES_UPSERT', 'MESSAGES_UPDATE'
      process_evolution_message_events(channel, params)
    when 'CONNECTION_UPDATE', 'QRCODE_UPDATED'
      Custom::Whatsapp::Evolution::ConnectionService.new(channel).handle_event(params)
    end
  end

  private

  def evolution_envelope?(params)
    params[:event].present? && params[:instance].present?
  end

  def find_evolution_channel(params)
    instance_name = params[:instance_name].presence || params[:instance]
    Channel::Whatsapp.find_by(
      provider: 'evolution',
      provider_config: { instance_name: instance_name }
    ) || Channel::Whatsapp.where(provider: 'evolution')
                          .where("provider_config->>'instance_name' = ?", instance_name)
                          .first
  end

  def process_evolution_message_events(channel, params)
    Array.wrap(params[:data]).each do |data_item|
      normalized = Custom::Whatsapp::Webhooks::EvolutionNormalizer.new(
        channel: channel,
        envelope: params.merge(data: data_item)
      ).perform
      next if normalized.blank?

      flat_params = normalized.merge(phone_number: channel.phone_number)
      sender_id = evolution_contact_sender_id(flat_params)
      process_with_evolution_message_lock(channel, sender_id) do
        process_events(channel, flat_params)
      end
    end
  end

  def process_with_evolution_message_lock(channel, sender_id, &)
    return yield if sender_id.blank?

    key = format(
      ::Redis::Alfred::WHATSAPP_MESSAGE_MUTEX,
      inbox_id: channel.inbox.id,
      sender_id: sender_id
    )
    with_lock(key, EVOLUTION_MESSAGE_LOCK_TTL, &)
  end

  def evolution_contact_sender_id(params)
    params.dig(:messages, 0, :from) ||
      params.dig(:statuses, 0, :recipient_id)
  end
end

Webhooks::WhatsappEventsJob.prepend_mod_with('Webhooks::WhatsappEventsJob')
