# frozen_string_literal: true

class Custom::Whatsapp::Evolution::LostMessagesReconciliationService
  LOOKBACK_HOURS = 6
  PAGE_SIZE = 50
  MAX_PAGES = 20

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
    response = api_client.connection_state
    return false unless response.success?

    state = response.parsed_response.dig('instance', 'state') ||
            response.parsed_response['state']
    state.to_s == 'open'
  rescue StandardError => e
    Rails.logger.warn(
      "[EVOLUTION] lost messages connection check failed channel=#{channel.id}: #{e.message}"
    )
    channel.provider_config['connection_status'].to_s == 'open'
  end

  def missing_payloads
    remote_messages.reject { |entry| skip_reconciliation_entry?(entry) }
  end

  def skip_reconciliation_entry?(entry)
    key = entry['key'] || entry[:key] || {}
    source_id = key['id'] || key[:id]
    return true if source_id.blank?
    return true if existing_source_ids.include?(source_id)

    false
  end

  def remote_messages
    messages = []
    page = 1

    loop do
      records, total_pages = fetch_reconciliation_page(page)
      break if records.blank?

      messages.concat(records)
      break if page >= MAX_PAGES
      break if total_pages.zero? || page >= total_pages

      page += 1
    end

    messages
  end

  def fetch_reconciliation_page(page)
    response = api_client.find_messages(
      page: page,
      offset: PAGE_SIZE,
      where: {
        messageTimestamp: {
          gte: lookback_timestamp,
          lte: Time.current.utc.iso8601(3)
        }
      }
    )
    return [[], 0] unless response.success?

    parsed = response.parsed_response || {}
    [Array.wrap(parsed.dig('messages', 'records')), parsed.dig('messages', 'pages').to_i]
  end

  def existing_source_ids
    @existing_source_ids ||= channel.inbox.messages
                                    .where('created_at >= ?', LOOKBACK_HOURS.hours.ago)
                                    .where.not(source_id: [nil, ''])
                                    .pluck(:source_id)
                                    .to_set
  end

  def lookback_timestamp
    LOOKBACK_HOURS.hours.ago.utc.iso8601(3)
  end

  def import_message(data_item)
    key = data_item['key'] || data_item[:key] || {}
    return import_phone_outgoing_message(data_item) if from_me_message?(key)

    import_inbound_message(data_item)
  end

  def from_me_message?(key)
    ActiveModel::Type::Boolean.new.cast(key['fromMe'] || key[:fromMe])
  end

  def import_phone_outgoing_message(data_item)
    return if ignore_from_me_echo?

    Custom::Whatsapp::Evolution::PhoneOutgoingSyncService.new(channel: channel, data: data_item).perform
  end

  def import_inbound_message(data_item)
    envelope = {
      event: 'MESSAGES_UPSERT',
      instance: channel.provider_config['instance_name'],
      data: data_item
    }
    normalized = Custom::Whatsapp::Webhooks::EvolutionNormalizer.new(
      channel: channel,
      envelope: envelope
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

  def ignore_from_me_echo?
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['ignore_from_me_echo'])
  end
end
