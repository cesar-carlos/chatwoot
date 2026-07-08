# frozen_string_literal: true

class Custom::Whatsapp::Evolution::WebhookDispatcher
  def dispatch(channel, params)
    case params[:event]
    when 'MESSAGES_UPSERT', 'MESSAGES_UPDATE'
      process_message_events(channel, params)
    when 'MESSAGES_DELETE'
      process_delete_events(channel, params)
    when 'MESSAGES_EDITED', 'SEND_MESSAGE_UPDATE'
      # SEND_MESSAGE_UPDATE (dotted: send.message.update) is the event name
      # used by some Evolution versions for the same "message was edited"
      # semantics as MESSAGES_EDITED — same payload shape, same handler.
      process_edit_events(channel, params)
    when 'CONTACTS_UPSERT', 'CONTACTS_UPDATE'
      Custom::Whatsapp::Evolution::ContactsSyncJob.perform_later(channel.id, params[:data])
    when 'GROUPS_UPSERT', 'GROUP_UPDATE'
      process_group_events(channel, params)
    when 'CONNECTION_UPDATE', 'QRCODE_UPDATED'
      Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).handle_event(params)
    else
      instance_name = params[:instance_name].presence || params[:instance]
      Rails.logger.warn(
        "[EVOLUTION] unhandled event=#{params[:event]} instance=#{instance_name}"
      )
    end
  end

  private

  def process_group_events(channel, params)
    Array.wrap(params[:data]).each do |data_item|
      unless data_item.is_a?(Hash)
        log_malformed_data_item(params[:event], data_item)
        next
      end

      group_jid = extract_group_jid(data_item)
      next if group_jid.blank?

      Custom::Whatsapp::Evolution::GroupMetadataService.new(channel: channel).warm_cache!(group_jid)
    end
  end

  def extract_group_jid(data_item)
    data = data_item.with_indifferent_access
    data[:id].presence ||
      data.dig(:key, :remoteJid).presence ||
      data[:remoteJid].presence ||
      data.dig(:group, :id).presence
  end

  def process_message_events(channel, params)
    Array.wrap(params[:data]).each do |data_item|
      unless data_item.is_a?(Hash)
        log_malformed_data_item(params[:event], data_item)
        next
      end

      process_message_item(channel, params, data_item)
    end
  end

  def process_message_item(channel, params, data_item)
    if status_update?(params[:event], data_item)
      process_status_update(channel, params, data_item)
      return
    end

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
      Custom::Whatsapp::Evolution::InboundMessageProcessor.process(channel, flat_params)
    end
  end

  def process_status_update(channel, params, data_item)
    normalized = Custom::Whatsapp::Webhooks::EvolutionNormalizer.new(
      channel: channel,
      envelope: params.merge(data: data_item)
    ).perform
    return log_normalizer_skipped(params[:event], data_item) if normalized.blank?

    flat_params = normalized.merge(phone_number: channel.phone_number)
    sender_id = contact_sender_id(flat_params)
    with_message_lock(channel, sender_id) do
      Custom::Whatsapp::Evolution::InboundMessageProcessor.process(channel, flat_params)
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
      unless data_item.is_a?(Hash)
        log_malformed_data_item(params[:event], data_item)
        next
      end

      process_mutation_event(channel, data_item) do
        Custom::Whatsapp::Evolution::MessageDeleteSyncService.new(channel: channel, data: data_item).perform
      end
    end
  end

  def process_edit_events(channel, params)
    Array.wrap(params[:data]).each do |data_item|
      unless data_item.is_a?(Hash)
        log_malformed_data_item(params[:event], data_item)
        next
      end

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
    Custom::Whatsapp::Evolution::MessageMutex.with_lock(channel, sender_id, &)
  end

  def message_key(data_item)
    data_item.is_a?(Hash) ? (data_item['key'] || data_item[:key] || {}) : {}
  end

  def status_update?(event, data_item)
    return false unless event == 'MESSAGES_UPDATE' && data_item.is_a?(Hash)

    data = data_item.with_indifferent_access
    evolution_flat_status?(data) || baileys_status?(data)
  end

  def evolution_flat_status?(data)
    data[:keyId].present? && data[:status].present?
  end

  def baileys_status?(data)
    key = data[:key] || {}
    update = data[:update] || {}
    key[:id].present? && !update[:status].nil?
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

  def log_malformed_data_item(event, data_item)
    Rails.logger.warn(
      "[EVOLUTION] malformed data item event=#{event} class=#{data_item.class}"
    )
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
