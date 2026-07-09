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
    key = format(Redis::RedisKeys::EVOLUTION_GO_IMPORT_REMOTE_JIDS, channel_id: runtime.channel.id)
    stored = ::Redis::Alfred.get(key)
    return [] if stored.blank?

    JSON.parse(stored)
  rescue JSON::ParserError
    []
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
