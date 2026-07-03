# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ImportService
  BATCH_SIZE = 50
  PAGES_PER_RUN = 5
  RATE_LIMIT_SLEEP = 0.15
  IMPORT_LOCK_TTL = 2.hours.to_i

  attr_reader :channel, :force

  def initialize(channel:, force: false)
    @channel = channel
    @force = force
    @runtime = Custom::Whatsapp::Evolution::Import::Runtime.new(channel: channel)
    @import_lock_acquired = false
  end

  def perform
    return unless ready_to_import?

    @runtime.reset_cursor! if force
    @runtime.mark_running! unless @runtime.import_running?

    run_batches!
    requeue_if_pending!
  rescue StandardError => e
    @runtime.mark_failed!(e)
  ensure
    release_import_lock!
  end

  private

  def ready_to_import?
    return false unless @runtime.import_enabled?
    return false if @runtime.import_running? && !force

    acquire_import_lock!
  end

  def acquire_import_lock!
    @import_lock_acquired = ::Redis::Alfred.set(import_lock_key, true, nx: true, ex: IMPORT_LOCK_TTL)
    @import_lock_acquired
  end

  def release_import_lock!
    return unless @import_lock_acquired

    ::Redis::Alfred.delete(import_lock_key)
    @import_lock_acquired = false
  end

  def import_lock_key
    format(Redis::RedisKeys::EVOLUTION_IMPORT_LOCK, channel_id: channel.id)
  end

  def run_batches!
    PAGES_PER_RUN.times do
      break if @runtime.import_completed?

      process_current_phase!
      sleep(RATE_LIMIT_SLEEP)
    end
  end

  def process_current_phase!
    case @runtime.current_phase
    when 'contacts'
      contacts_importer.import_batch!
    when 'messages'
      messages_importer.import_batch!
    else
      @runtime.mark_completed!
    end
  end

  def contacts_importer
    @contacts_importer ||= Custom::Whatsapp::Evolution::Import::ContactsImporter.new(
      runtime: @runtime,
      api_client: api_client
    )
  end

  def messages_importer
    @messages_importer ||= Custom::Whatsapp::Evolution::Import::MessagesImporter.new(
      runtime: @runtime,
      api_client: api_client,
      channel: channel
    )
  end

  def api_client
    @api_client ||= Custom::Whatsapp::Evolution::ApiClient.for_channel(channel)
  end

  def requeue_if_pending!
    return if @runtime.import_completed?

    Custom::Whatsapp::Evolution::ImportJob.set(wait: 5.seconds).perform_later(channel.id)
  end
end
