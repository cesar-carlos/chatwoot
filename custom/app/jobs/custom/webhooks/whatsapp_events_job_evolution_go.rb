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
    case params[:event].to_s.upcase
    when 'MESSAGE'
      process_message_event(channel, params)
    when 'MESSAGE_DELETE', 'MESSAGES_DELETE', 'DELETE'
      process_delete_event(channel, params)
    when 'MESSAGES_EDITED', 'MESSAGE_EDIT', 'SEND_MESSAGE_UPDATE'
      process_edit_event(channel, params)
    when 'READ_RECEIPT', 'RECEIPT'
      process_read_receipt_event(channel, params)
    when 'CONNECTION', 'CONNECTED', 'DISCONNECTED', 'LOGGEDOUT', 'QRCODE'
      Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: channel).handle_event(params)
    when 'HISTORY_SYNC'
      process_history_sync_event(channel, params)
    when 'GROUP'
      process_group_event(channel, params)
    when 'SEND_MESSAGE'
      nil
    else
      Rails.logger.info("[EVOLUTION_GO] ignored event=#{params[:event]} channel=#{channel.id}")
    end
  end

  def process_message_event(channel, params)
    delete_key = inbound_delete_key(channel, params)
    if delete_key.present?
      process_inbound_delete(channel, delete_key)
      return
    end

    edit_payload = inbound_edit_payload(channel, params)
    if edit_payload.present?
      process_inbound_edit(channel, edit_payload)
      return
    end

    canonical = Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.canonicalize_data(params[:data])
    key = canonical['key'] || canonical[:key] || {}

    if from_me_message?(key)
      if ignore_from_me_echo?(channel)
        log_blank_normalization(channel, params, reason: 'fromMe echo ignored')
        return
      end

      process_from_me_message(channel, params)
      return
    end

    normalized = Custom::Whatsapp::Webhooks::EvolutionGoNormalizer.new(channel, params).perform
    if normalized.blank?
      log_blank_normalization(channel, params, reason: 'normalizer returned blank')
      return
    end

    deliver_inbound_payload(channel, normalized)
  end

  def process_read_receipt_event(channel, params)
    normalized = Custom::Whatsapp::Webhooks::EvolutionGoReadReceiptNormalizer.new(channel, params).perform
    if normalized.blank?
      log_blank_normalization(channel, params, reason: 'read receipt normalizer returned blank')
      return
    end

    deliver_inbound_payload(channel, normalized)
  end

  def process_delete_event(channel, params)
    delete_key = inbound_delete_key(channel, params)
    return if delete_key.blank?

    process_inbound_delete(channel, delete_key)
  end

  def process_history_sync_event(channel, params)
    Custom::Whatsapp::EvolutionGo::Import::HistorySyncProcessor.new(
      channel: channel,
      data: params[:data]
    ).perform
  end

  def process_group_event(channel, params)
    group_jid = extract_group_jid(params[:data])
    return if group_jid.blank?

    Custom::Whatsapp::Evolution::GroupMetadataFetchJob.perform_later(channel.id, group_jid)
  end

  def extract_group_jid(data)
    return if data.blank?

    data = data.with_indifferent_access
    jid = data[:groupJid] || data[:jid] || data[:id] ||
          data.dig(:key, :remoteJid) || data.dig('key', 'remoteJid')
    jid.to_s.include?('@g.us') ? jid.to_s : nil
  end

  def process_edit_event(channel, params)
    edit_payload = inbound_edit_payload(channel, params)
    return if edit_payload.blank?

    process_inbound_edit(channel, edit_payload)
  end

  def inbound_edit_payload(channel, params)
    return unless mark_inbound_edited?(channel)

    Custom::Whatsapp::EvolutionGo::MessageEditPayloadExtractor.extract_edit_payload(
      params[:data],
      event: params[:event]
    )
  end

  def process_inbound_edit(channel, edit_payload)
    key = edit_payload[:key] || edit_payload['key']
    sender_id = key['remoteJid'] || key[:remoteJid] || key['id'] || key[:id]
    Custom::Whatsapp::Evolution::MessageMutex.with_lock(channel, sender_id) do
      Custom::Whatsapp::EvolutionGo::MessageEditSyncService.new(
        channel: channel,
        data: edit_payload
      ).perform
    end
  end

  def inbound_delete_key(channel, params)
    return unless mark_inbound_deleted?(channel)

    Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor.extract_delete_key(
      params[:data],
      event: params[:event]
    )
  end

  def process_inbound_delete(channel, key)
    sender_id = key['remoteJid'] || key[:remoteJid] || key['id'] || key[:id]
    Custom::Whatsapp::Evolution::MessageMutex.with_lock(channel, sender_id) do
      Custom::Whatsapp::EvolutionGo::MessageDeleteSyncService.new(
        channel: channel,
        data: { key: key }
      ).perform
    end
  end

  def mark_inbound_deleted?(channel)
    config = channel.provider_config || Custom::Whatsapp::EvolutionGo::ProviderConfigDefaults::DEFAULTS
    ActiveModel::Type::Boolean.new.cast(config['mark_inbound_deleted'])
  end

  def mark_inbound_edited?(channel)
    config = channel.provider_config || Custom::Whatsapp::EvolutionGo::ProviderConfigDefaults::DEFAULTS
    ActiveModel::Type::Boolean.new.cast(config['mark_inbound_edited'])
  end

  def process_from_me_message(channel, params)
    sender_id = outgoing_sender_id(params[:data])
    Custom::Whatsapp::Evolution::MessageMutex.with_lock(channel, sender_id) do
      Custom::Whatsapp::EvolutionGo::PhoneOutgoingSyncService.new(channel: channel, data: params[:data]).perform
    end
  end

  def deliver_inbound_payload(channel, normalized)
    flat_params = normalized.merge(phone_number: channel.phone_number)
    sender_id = flat_params.dig(:messages, 0, :from) || flat_params.dig(:statuses, 0, :recipient_id)
    Custom::Whatsapp::Evolution::MessageMutex.with_lock(channel, sender_id) do
      Custom::Whatsapp::EvolutionGo::InboundMessageProcessor.process(channel, flat_params)
    end
  end

  def from_me_message?(key)
    ActiveModel::Type::Boolean.new.cast(key['fromMe'] || key[:fromMe])
  end

  def ignore_from_me_echo?(channel)
    config = channel.provider_config || Custom::Whatsapp::EvolutionGo::ProviderConfigDefaults::DEFAULTS
    ActiveModel::Type::Boolean.new.cast(config['ignore_from_me_echo'])
  end

  def outgoing_sender_id(data)
    canonical = Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.canonicalize_data(data)
    key = canonical['key'] || canonical[:key] || {}
    jid = key['remoteJid'] || key[:remoteJid]
    Custom::Whatsapp::EvolutionGo::JidResolver.new(channel.provider_config).phone_from_jid(jid)
  end

  def log_blank_normalization(channel, params, reason:)
    Rails.logger.warn(
      "[EVOLUTION_GO] skipped event=#{params[:event]} channel=#{channel.id} reason=#{reason}"
    )
  end
end

Webhooks::WhatsappEventsJob.prepend(Custom::Webhooks::WhatsappEventsJobEvolutionGo)
