# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ImportService
  BATCH_SIZE = 50
  PAGES_PER_RUN = 5
  RATE_LIMIT_SLEEP = 0.15

  attr_reader :channel, :force

  def initialize(channel:, force: false)
    @channel = channel
    @force = force
    @runtime = Custom::Whatsapp::Evolution::Import::Runtime.new(channel: channel)
  end

  def perform
    return unless @runtime.import_enabled?
    return if @runtime.import_running? && !force

    @runtime.reset_cursor! if force
    @runtime.mark_running! unless @runtime.import_running?

    run_batches!
    requeue_if_pending!
  rescue StandardError => e
    @runtime.mark_failed!(e)
    raise
  end

  private

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
    @api_client ||= Custom::Whatsapp::Evolution::ApiClient.new(
      base_url: @runtime.config['base_url'],
      api_key: @runtime.config['api_key'],
      instance_name: @runtime.config['instance_name']
    )
  end

  def requeue_if_pending!
    return if @runtime.import_completed?

    Custom::Whatsapp::Evolution::ImportJob.set(wait: 5.seconds).perform_later(channel.id)
  end
end
