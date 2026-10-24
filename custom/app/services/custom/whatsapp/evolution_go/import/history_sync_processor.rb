# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::Import::HistorySyncProcessor
  pattr_initialize [:channel!, :data!]

  def perform
    return unless import_messages_enabled?

    records = extract_message_records
    return if records.blank?

    imported = 0
    records.each do |record|
      imported += 1 if import_record(record)
    end
    update_import_stats!(imported) if imported.positive?
  end

  private

  def import_messages_enabled?
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['import_messages'])
  end

  def extract_message_records
    payload = data.with_indifferent_access
    records = payload[:messages] || payload[:Messages]
    return [payload] if records.blank? && payload[:key].present?
    return [payload] if records.blank? && payload[:Info].present?

    Array.wrap(records)
  end

  def import_record(record)
    protocol_result = apply_protocol_mutation!(record)
    return protocol_result unless protocol_result.nil?

    source_id = extract_source_id(record).to_s
    return false if source_id.blank? || duplicate_source_id?(source_id)

    import_record_by_direction!(record)
    return false unless channel.inbox.messages.exists?(source_id: source_id)

    stamp_imported_message!(source_id)
    true
  rescue MutexApplicationJob::LockAcquisitionError
    raise
  rescue StandardError => e
    Rails.logger.warn("[EVOLUTION_GO] history sync import failed: #{e.message}")
    false
  end

  # nil: not a protocol envelope. true/false: consumed, and whether a row changed.
  def apply_protocol_mutation!(record)
    delete_key = Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor.extract_delete_key(record)
    return apply_delete_mutation!(delete_key) if delete_key.present?

    edit_payload = Custom::Whatsapp::EvolutionGo::MessageEditPayloadExtractor.extract_edit_payload(record)
    return nil if edit_payload.blank?

    apply_edit_mutation!(edit_payload)
  end

  def apply_delete_mutation!(delete_key)
    source_id = (delete_key['id'] || delete_key[:id]).to_s
    message = channel.inbox.messages.find_by(source_id: source_id)
    Custom::Whatsapp::EvolutionGo::MessageDeleteSyncService.new(
      channel: channel,
      data: { key: delete_key }
    ).perform
    message.present? && message.reload.content_attributes.to_h['deleted'] == true
  end

  def apply_edit_mutation!(edit_payload)
    key = (edit_payload[:key] || edit_payload['key'] || {}).with_indifferent_access
    message = channel.inbox.messages.find_by(source_id: key[:id])
    previous = message&.content
    Custom::Whatsapp::EvolutionGo::MessageEditSyncService.new(
      channel: channel,
      data: edit_payload
    ).perform
    message.present? && message.reload.content != previous
  end

  def duplicate_source_id?(source_id)
    source_id.present? && channel.inbox.messages.exists?(source_id: source_id)
  end

  def import_record_by_direction!(record)
    canonical = Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.canonicalize_data(record)
    key = canonical['key'] || canonical[:key] || {}
    return import_from_me_record!(record) if from_me_record?(key)

    import_inbound_record!(record)
  end

  def from_me_record?(key)
    ActiveModel::Type::Boolean.new.cast(key['fromMe'] || key[:fromMe])
  end

  def import_from_me_record!(record)
    Custom::Whatsapp::EvolutionGo::PhoneOutgoingSyncService.new(channel: channel, data: record).perform
  end

  def import_inbound_record!(record)
    envelope = {
      event: 'MESSAGE',
      instance: channel.provider_config['instance_name'],
      data: record
    }
    normalized = Custom::Whatsapp::Webhooks::EvolutionGoNormalizer.new(channel, envelope).perform
    return if normalized.blank?

    Custom::Whatsapp::EvolutionGo::InboundMessageProcessor.process(
      channel,
      normalized.merge(phone_number: channel.phone_number)
    )
  end

  def extract_source_id(record)
    canonical = Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.canonicalize_data(record)
    key = canonical['key'] || canonical[:key] || {}
    key['id'] || key[:id]
  end

  def stamp_imported_message!(source_id)
    return if source_id.blank?

    message = channel.inbox.messages.find_by(source_id: source_id)
    return if message.blank?

    attrs = (message.content_attributes || {}).merge('history_import' => true)
    message.update!(content_attributes: attrs)
  end

  def update_import_stats!(count)
    runtime = Custom::Whatsapp::EvolutionGo::Import::Runtime.new(channel: channel)
    runtime.update_stats!(messages_imported: count)
  end
end
