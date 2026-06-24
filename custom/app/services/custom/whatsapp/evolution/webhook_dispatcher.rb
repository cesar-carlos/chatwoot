# frozen_string_literal: true

class Custom::Whatsapp::Evolution::WebhookDispatcher
  MESSAGE_LOCK_TTL = 30.seconds

  pattr_initialize [:job!]

  def dispatch(channel, params)
    case params[:event]
    when 'MESSAGES_UPSERT', 'MESSAGES_UPDATE'
      process_message_events(channel, params)
    when 'MESSAGES_DELETE'
      process_delete_events(channel, params)
    when 'MESSAGES_EDITED'
      process_edit_events(channel, params)
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

  private

  def process_message_events(channel, params)
    Array.wrap(params[:data]).each do |data_item|
      next unless data_item.is_a?(Hash)

      process_message_item(channel, params, data_item)
    end
  end

  def process_message_item(channel, params, data_item)
    key = message_key(data_item)
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
    sender_id = contact_sender_id(flat_params)
    with_message_lock(channel, sender_id) do
      job.send(:process_events, channel, flat_params)
    end
  end

  def process_from_me_message(channel, event, data_item, key)
    if ignore_from_me_echo?(channel)
      log_normalizer_skipped(event, data_item)
      return
    end

    sender_id = outgoing_sender_id(key)
    with_message_lock(channel, sender_id) do
      Custom::Whatsapp::Evolution::PhoneOutgoingSyncService.new(channel: channel, data: data_item).perform
    end
  end

  def process_delete_events(channel, params)
    Array.wrap(params[:data]).each do |data_item|
      next unless data_item.is_a?(Hash)

      process_mutation_event(channel, data_item) do
        Custom::Whatsapp::Evolution::MessageDeleteSyncService.new(channel: channel, data: data_item).perform
      end
    end
  end

  def process_edit_events(channel, params)
    Array.wrap(params[:data]).each do |data_item|
      next unless data_item.is_a?(Hash)

      process_mutation_event(channel, data_item) do
        Custom::Whatsapp::Evolution::MessageEditSyncService.new(channel: channel, data: data_item).perform
      end
    end
  end

  def process_mutation_event(channel, data_item, &)
    key = message_key(data_item)
    sender_id = key['remoteJid'] || key[:remoteJid] || key['id'] || key[:id]
    with_message_lock(channel, sender_id, &)
  end

  def with_message_lock(channel, sender_id, &)
    return yield if sender_id.blank?

    key = format(
      ::Redis::Alfred::WHATSAPP_MESSAGE_MUTEX,
      inbox_id: channel.inbox.id,
      sender_id: sender_id
    )
    job.send(:with_lock, key, MESSAGE_LOCK_TTL, &)
  end

  def message_key(data_item)
    data_item.is_a?(Hash) ? (data_item['key'] || data_item[:key] || {}) : {}
  end

  def from_me_message?(key)
    ActiveModel::Type::Boolean.new.cast(key['fromMe'] || key[:fromMe])
  end

  def ignore_from_me_echo?(channel)
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['ignore_from_me_echo'])
  end

  def outgoing_sender_id(key)
    key['remoteJid'] || key[:remoteJid] || key['id'] || key[:id]
  end

  def contact_sender_id(params)
    params.dig(:messages, 0, :from) ||
      params.dig(:statuses, 0, :recipient_id)
  end

  def log_normalizer_skipped(event, data_item)
    key = message_key(data_item)
    Rails.logger.warn(
      "[EVOLUTION] normalizer skipped event=#{event} " \
      "id=#{key['id'] || key[:id]} fromMe=#{key['fromMe'] || key[:fromMe]} " \
      "remoteJid=#{key['remoteJid'] || key[:remoteJid]}"
    )
  end
end
