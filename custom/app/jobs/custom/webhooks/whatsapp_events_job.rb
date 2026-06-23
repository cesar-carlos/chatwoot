# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength -- Evolution webhook dispatch extends upstream job
module Custom::Webhooks::WhatsappEventsJob
  EVOLUTION_MESSAGE_LOCK_TTL = 30.seconds

  def perform(params = {})
    params = params.with_indifferent_access
    return super(params) unless evolution_envelope?(params)

    params = params.merge(event: Custom::Whatsapp::Evolution::EventNames.normalize(params[:event]))

    channel = find_evolution_channel(params)
    unless channel
      Rails.logger.warn("[EVOLUTION] unknown instance=#{params[:instance]}")
      return
    end

    if channel_is_inactive?(channel)
      Rails.logger.warn("[EVOLUTION] inactive channel instance=#{params[:instance]}")
      return
    end

    dispatch_evolution_event(channel, params)
  end

  private

  def dispatch_evolution_event(channel, params)
    case params[:event]
    when 'MESSAGES_UPSERT', 'MESSAGES_UPDATE'
      process_evolution_message_events(channel, params)
    when 'MESSAGES_DELETE'
      process_evolution_delete_events(channel, params)
    when 'MESSAGES_EDITED'
      process_evolution_edit_events(channel, params)
    when 'CONTACTS_UPSERT', 'CONTACTS_UPDATE'
      Custom::Whatsapp::Evolution::ContactsSyncJob.perform_later(channel.id, params[:data])
    when 'CONNECTION_UPDATE', 'QRCODE_UPDATED'
      Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).handle_event(params)
    else
      Rails.logger.warn(
        "[EVOLUTION] unhandled event=#{params[:event]} instance=#{params[:instance]}"
      )
    end
  end

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

  def process_evolution_message_events(channel, params)
    Array.wrap(params[:data]).each do |data_item|
      next unless data_item.is_a?(Hash)

      process_evolution_message_item(channel, params, data_item)
    end
  end

  def process_evolution_message_item(channel, params, data_item)
    key = evolution_message_key(data_item)
    if from_me_message?(key)
      process_from_me_message(channel, params[:event], data_item, key)
      return
    end

    normalized = Custom::Whatsapp::Webhooks::EvolutionNormalizer.new(
      channel: channel,
      envelope: params.merge(data: data_item)
    ).perform
    return log_normalizer_skipped(params[:event], data_item) if normalized.blank?

    flat_params = normalized.merge(phone_number: channel.phone_number)
    sender_id = evolution_contact_sender_id(flat_params)
    process_with_evolution_message_lock(channel, sender_id) do
      process_events(channel, flat_params)
    end
  end

  def process_from_me_message(channel, event, data_item, key)
    if ignore_from_me_echo?(channel)
      log_normalizer_skipped(event, data_item)
      return
    end

    sender_id = evolution_outgoing_sender_id(key)
    process_with_evolution_message_lock(channel, sender_id) do
      Custom::Whatsapp::Evolution::PhoneOutgoingSyncService.new(channel: channel, data: data_item).perform
    end
  end

  def evolution_message_key(data_item)
    data_item.is_a?(Hash) ? (data_item['key'] || data_item[:key] || {}) : {}
  end

  def from_me_message?(key)
    ActiveModel::Type::Boolean.new.cast(key['fromMe'] || key[:fromMe])
  end

  def ignore_from_me_echo?(channel)
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['ignore_from_me_echo'])
  end

  def evolution_outgoing_sender_id(key)
    key['remoteJid'] || key[:remoteJid] || key['id'] || key[:id]
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

  def process_evolution_delete_events(channel, params)
    Array.wrap(params[:data]).each do |data_item|
      next unless data_item.is_a?(Hash)

      process_evolution_mutation_event(channel, data_item) do
        Custom::Whatsapp::Evolution::MessageDeleteSyncService.new(channel: channel, data: data_item).perform
      end
    end
  end

  def process_evolution_edit_events(channel, params)
    Array.wrap(params[:data]).each do |data_item|
      next unless data_item.is_a?(Hash)

      process_evolution_mutation_event(channel, data_item) do
        Custom::Whatsapp::Evolution::MessageEditSyncService.new(channel: channel, data: data_item).perform
      end
    end
  end

  def process_evolution_mutation_event(channel, data_item, &)
    key = data_item.is_a?(Hash) ? (data_item['key'] || data_item[:key] || {}) : {}
    sender_id = key['remoteJid'] || key[:remoteJid] || key['id'] || key[:id]
    process_with_evolution_message_lock(channel, sender_id, &)
  end

  def evolution_contact_sender_id(params)
    params.dig(:messages, 0, :from) ||
      params.dig(:statuses, 0, :recipient_id)
  end

  def log_normalizer_skipped(event, data_item)
    key = data_item.is_a?(Hash) ? (data_item['key'] || data_item[:key] || {}) : {}
    Rails.logger.warn(
      "[EVOLUTION] normalizer skipped event=#{event} " \
      "id=#{key['id'] || key[:id]} fromMe=#{key['fromMe'] || key[:fromMe]} " \
      "remoteJid=#{key['remoteJid'] || key[:remoteJid]}"
    )
  end
end
# rubocop:enable Metrics/ModuleLength

Webhooks::WhatsappEventsJob.prepend_mod_with('Webhooks::WhatsappEventsJob')
