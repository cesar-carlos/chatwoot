# frozen_string_literal: true

class Custom::Whatsapp::Evolution::LostMessagesReconciliationService
  LOOKBACK_HOURS = 6
  PAGE_SIZE = 50

  pattr_initialize [:channel!]

  def perform
    return unless sync_enabled?
    return unless connection_open?

    missing_payloads.each { |payload| import_message(payload) }
  rescue StandardError => e
    Rails.logger.warn(
      "[EVOLUTION] lost messages reconciliation failed channel=#{channel.id}: #{e.message}"
    )
  end

  private

  def sync_enabled?
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['sync_lost_messages'])
  end

  def connection_open?
    channel.provider_config['connection_status'].to_s == 'open'
  end

  def missing_payloads
    remote_messages.filter_map do |entry|
      key = entry['key'] || entry[:key] || {}
      source_id = key['id'] || key[:id]
      next if source_id.blank?
      next if existing_source_ids.include?(source_id)

      entry
    end
  end

  def remote_messages
    response = api_client.find_messages(
      page: 1,
      offset: PAGE_SIZE,
      where: {
        messageTimestamp: {
          gte: lookback_timestamp
        }
      }
    )
    return [] unless response.success?

    Array.wrap(response.parsed_response)
  end

  def existing_source_ids
    @existing_source_ids ||= channel.inbox.messages
                                    .where('created_at >= ?', LOOKBACK_HOURS.hours.ago)
                                    .where.not(source_id: [nil, ''])
                                    .pluck(:source_id)
                                    .to_set
  end

  def lookback_timestamp
    LOOKBACK_HOURS.hours.ago.to_i
  end

  def import_message(data_item)
    envelope = {
      event: 'MESSAGES_UPSERT',
      instance: channel.provider_config['instance_name'],
      data: data_item
    }
    normalized = Custom::Whatsapp::Webhooks::EvolutionNormalizer.new(
      channel: channel,
      envelope: envelope,
      import_mode: true
    ).perform
    return if normalized.blank?

    Whatsapp::IncomingMessageService.new(
      inbox: channel.inbox,
      params: normalized.merge(phone_number: channel.phone_number)
    ).perform
  end

  def api_client
    Custom::Whatsapp::Evolution::ApiClient.for_channel(channel)
  end
end
