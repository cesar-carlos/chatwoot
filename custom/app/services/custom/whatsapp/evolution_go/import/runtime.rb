# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::Import::Runtime
  attr_reader :channel

  def initialize(channel:)
    @channel = channel
    @cursor = nil
  end

  def inbox
    @inbox ||= channel.inbox
  end

  def account
    @account ||= inbox.account
  end

  def config
    channel.provider_config || {}
  end

  def cursor
    @cursor ||= (config['import_cursor'] || {}).with_indifferent_access
  end

  def import_contacts?
    ActiveModel::Type::Boolean.new.cast(config['import_contacts'])
  end

  def import_messages?
    ActiveModel::Type::Boolean.new.cast(config['import_messages'])
  end

  def import_enabled?
    import_contacts? || import_messages?
  end

  STALE_RUNNING_AFTER = 2.hours + 15.minutes

  def import_running?
    config['import_status'] == 'running'
  end

  def import_stale?
    return false unless import_running?

    heartbeat = config['import_heartbeat_at'] || config['import_started_at']
    return true if heartbeat.blank?

    Time.zone.parse(heartbeat) < STALE_RUNNING_AFTER.ago
  rescue ArgumentError, TypeError
    true
  end

  def touch_heartbeat!
    persist_runtime!('import_heartbeat_at' => Time.current.iso8601)
  end

  def import_completed?
    config['import_status'] == 'completed' || cursor[:phase] == 'done'
  end

  def current_phase
    phase = cursor[:phase].to_s.presence
    return phase if phase.in?(%w[contacts messages done])
    return 'contacts' if import_contacts?
    return 'messages' if import_messages?

    'done'
  end

  def reset_cursor!
    ::Redis::Alfred.delete(
      format(Redis::RedisKeys::EVOLUTION_GO_IMPORT_REMOTE_JIDS, channel_id: channel.id)
    )
    initial_phase = import_contacts? ? 'contacts' : 'messages'
    persist_runtime!(
      'import_status' => 'idle',
      'import_cursor' => { 'phase' => initial_phase },
      'import_stats' => {},
      'import_error' => nil,
      'import_started_at' => nil,
      'import_completed_at' => nil,
      'import_failed_at' => nil
    )
  end

  def mark_running!
    persist_runtime!(
      'import_status' => 'running',
      'import_started_at' => Time.current.iso8601,
      'import_error' => nil,
      'import_failed_at' => nil,
      'import_cursor' => cursor.presence || { 'phase' => import_contacts? ? 'contacts' : 'messages' }
    )
  end

  def mark_completed!
    persist_runtime!(
      'import_status' => 'completed',
      'import_completed_at' => Time.current.iso8601,
      'import_cursor' => (config['import_cursor'] || {}).merge('phase' => 'done')
    )
    clear_contacts_cache!
  end

  def mark_failed!(error)
    persist_runtime!(
      'import_status' => 'failed',
      'import_error' => error.message,
      'import_failed_at' => Time.current.iso8601
    )
    clear_contacts_cache!
    Rails.logger.error "[EVOLUTION_GO] import failed for channel #{channel.id}: #{error.message}"
  end

  def persist_cursor!(attrs)
    merged_cursor = cursor.merge(attrs.stringify_keys)
    persist_runtime!('import_cursor' => merged_cursor)
    @cursor = merged_cursor.with_indifferent_access
  end

  def update_stats!(attrs)
    stats = (config['import_stats'] || {}).dup
    attrs.each do |key, value|
      stats[key.to_s] = stats[key.to_s].to_i + value.to_i
    end
    persist_runtime!('import_stats' => stats)
  end

  def persist_runtime!(attrs)
    Custom::Whatsapp::EvolutionGo::ProviderConfigMerger.merge!(channel, attrs.stringify_keys)
  end

  def contacts_cache_key
    "evolution_go:import_contacts:#{channel.id}"
  end

  def clear_contacts_cache!
    Rails.cache.delete(contacts_cache_key)
  end
end
