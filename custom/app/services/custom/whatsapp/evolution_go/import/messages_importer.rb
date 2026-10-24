# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::Import::MessagesImporter
  include Custom::Whatsapp::EvolutionGo::Import::JidHelpers

  # Evolution Go `POST /chat/history-sync` takes `count` = number of messages
  # (OpenAPI HistorySyncRequestStruct), not a day window. The provider_config key
  # `days_limit_import_messages` is kept for backward compatibility with saved
  # inboxes / UI state; its value is the message count.
  DEFAULT_HISTORY_SYNC_COUNT = 100
  MAX_HISTORY_SYNC_COUNT = 1000

  def initialize(runtime:, api_client:)
    @runtime = runtime
    @api_client = api_client
  end

  def import_batch!
    remote_jids = load_remote_jids_from_redis
    remote_jids = seed_remote_jids! if remote_jids.blank? && runtime.cursor[:message_jid_index].to_i.zero?
    if remote_jids.blank?
      runtime.mark_completed!
      return
    end

    jid_index = runtime.cursor[:message_jid_index].to_i
    return runtime.mark_completed! if jid_index >= remote_jids.size

    remote_jid = remote_jids[jid_index]
    request_history_sync!(remote_jid)
    advance_cursor!(jid_index, remote_jids.size)
  end

  private

  attr_reader :runtime, :api_client

  def request_history_sync!(remote_jid)
    response = api_client.history_sync(
      chat: remote_jid,
      count: history_sync_count
    )
    Custom::Whatsapp::EvolutionGo::ApiClient.raise_unless_success!(
      response,
      'Failed to request Evolution Go history sync'
    )
  end

  def history_sync_count
    raw = runtime.config['days_limit_import_messages']
    value = raw.nil? ? DEFAULT_HISTORY_SYNC_COUNT : raw.to_i
    value.clamp(1, MAX_HISTORY_SYNC_COUNT)
  end

  def load_remote_jids_from_redis
    stored = ::Redis::Alfred.get(remote_jids_redis_key)
    return [] if stored.blank?

    JSON.parse(stored)
  rescue JSON::ParserError
    []
  end

  # Contacts phase normally fills this list. Messages-only import skips that
  # phase, so build the chat list from the provider address book and chats
  # already stored on the inbox before requesting history.
  def seed_remote_jids!
    jids = (remote_jids_from_provider + remote_jids_from_inbox).uniq.reject { |jid| skip_remote_jid?(jid) }
    save_remote_jids!(jids) if jids.present?
    jids
  end

  def remote_jids_from_provider
    response = api_client.user_contacts
    return [] unless response.success?

    extract_contacts_records(response.parsed_response).filter_map do |record|
      next unless record.is_a?(Hash)

      remote_jid_from_record(record).presence
    end
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.warn("[EVOLUTION_GO] history chat list failed channel=#{runtime.channel.id}: #{e.message}")
    []
  end

  def remote_jids_from_inbox
    jids = []
    runtime.inbox.contact_inboxes.includes(:contact).find_each do |contact_inbox|
      jid = history_jid_for(contact_inbox)
      jids << jid if jid.present?
    end
    jids
  end

  def history_jid_for(contact_inbox)
    stored_history_jid(contact_inbox).presence || phone_history_jid(contact_inbox)
  end

  def stored_history_jid(contact_inbox)
    contact = contact_inbox.contact
    attrs = (contact&.additional_attributes || {}).stringify_keys
    [
      attrs[Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY],
      contact&.identifier,
      attrs[Custom::Whatsapp::Evolution::GroupKeys::EVOLUTION_GROUP_JID_KEY],
      contact_inbox.source_id
    ].find { |value| value.to_s.include?('@') }&.to_s
  end

  def phone_history_jid(contact_inbox)
    digits = history_phone_digits(contact_inbox)
    return if digits.blank? || digits.start_with?('55000')

    "#{digits}@s.whatsapp.net"
  end

  def history_phone_digits(contact_inbox)
    contact_inbox.source_id.to_s.gsub(/\D/, '').presence ||
      contact_inbox.contact&.phone_number.to_s.gsub(/\D/, '').presence
  end

  def save_remote_jids!(jids)
    ::Redis::Alfred.set(remote_jids_redis_key, jids.to_json, ex: 7.days.to_i)
  end

  def remote_jids_redis_key
    format(Redis::RedisKeys::EVOLUTION_GO_IMPORT_REMOTE_JIDS, channel_id: runtime.channel.id)
  end

  def advance_cursor!(jid_index, jid_count)
    if jid_index + 1 >= jid_count
      runtime.mark_completed!
      return
    end

    runtime.persist_cursor!(
      'message_jid_index' => jid_index + 1,
      'message_page' => 1,
      'phase' => 'messages'
    )
  end
end
