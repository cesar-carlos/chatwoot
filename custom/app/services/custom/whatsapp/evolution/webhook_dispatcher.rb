# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength -- intentional Evolution webhook routing
class Custom::Whatsapp::Evolution::WebhookDispatcher
  MESSAGE_EVENTS = %w[MESSAGES_UPSERT MESSAGES_UPDATE].freeze
  EDIT_EVENTS = %w[MESSAGES_EDITED SEND_MESSAGE_UPDATE].freeze
  CONTACT_EVENTS = %w[CONTACTS_UPSERT CONTACTS_UPDATE].freeze
  GROUP_EVENTS = %w[GROUPS_UPSERT GROUP_UPDATE].freeze
  CONNECTION_EVENTS = %w[CONNECTION_UPDATE QRCODE_UPDATED].freeze

  def dispatch(channel, params)
    event = params[:event]
    return process_message_events(channel, params) if MESSAGE_EVENTS.include?(event)
    return process_delete_events(channel, params) if event == 'MESSAGES_DELETE'
    return process_edit_events(channel, params) if EDIT_EVENTS.include?(event)
    return sync_contacts(channel, params) if CONTACT_EVENTS.include?(event)
    return process_group_events(channel, params) if GROUP_EVENTS.include?(event)
    return handle_connection_event(channel, params) if CONNECTION_EVENTS.include?(event)

    log_unhandled_event(params)
  end

  private

  def sync_contacts(channel, params)
    Custom::Whatsapp::Evolution::ContactsSyncJob.perform_later(channel.id, params[:data])
  end

  def handle_connection_event(channel, params)
    Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).handle_event(params)
  end

  def log_unhandled_event(params)
    instance_name = params[:instance_name].presence || params[:instance]
    Rails.logger.warn(
      "[EVOLUTION] unhandled event=#{params[:event]} instance=#{instance_name}"
    )
  end

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

  # rubocop:disable Metrics/MethodLength -- reaction / status / from_me / inbound branches
  def process_message_item(channel, params, data_item)
    reaction_payload = Custom::Whatsapp::Evolution::MessageReactionPayloadExtractor
                       .extract_reaction_payload(data_item)
    if reaction_payload.present?
      process_inbound_reaction(channel, reaction_payload)
      return
    end

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
  # rubocop:enable Metrics/MethodLength

  def process_inbound_reaction(channel, reaction_payload)
    sender_id = reaction_payload.dig(:key, :remoteJid) ||
                reaction_payload.dig(:key, :id) ||
                reaction_payload[:reaction_message_id]
    with_message_lock(channel, sender_id) do
      Custom::Whatsapp::Evolution::MessageReactionSyncService.new(
        channel: channel,
        data: reaction_payload
      ).perform
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

# rubocop:enable Metrics/ClassLength
