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
    return true if apply_protocol_mutation!(record)

    source_id = extract_source_id(record)
    return false if duplicate_source_id?(source_id)

    import_record_by_direction!(record)
    stamp_imported_message!(source_id)
    true
  rescue StandardError => e
    Rails.logger.warn("[EVOLUTION_GO] history sync import failed: #{e.message}")
    false
  end

  def apply_protocol_mutation!(record)
    delete_key = Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor.extract_delete_key(record)
    if delete_key.present?
      Custom::Whatsapp::EvolutionGo::MessageDeleteSyncService.new(
        channel: channel,
        data: { key: delete_key }
      ).perform
      return true
    end

    edit_payload = Custom::Whatsapp::EvolutionGo::MessageEditPayloadExtractor.extract_edit_payload(record)
    return false if edit_payload.blank?

    Custom::Whatsapp::EvolutionGo::MessageEditSyncService.new(
      channel: channel,
      data: edit_payload
    ).perform
    true
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
