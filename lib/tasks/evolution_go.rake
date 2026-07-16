# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
namespace :evolution_go do
  desc 'Sync webhook subscriptions for all Evolution Go channels'
  task sync_webhooks: :environment do
    scope = Channel::Whatsapp.where(provider: 'evolution_go')
    synced = 0
    failed = 0

    scope.find_each do |channel|
      config = channel.provider_config || {}
      next if config['instance_id'].blank?

      service = Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: channel)
      events = service.webhook_subscribe_sync.sync!
      synced += 1
      puts "[EVOLUTION_GO] synced channel=#{channel.id} instance=#{channel.provider_config['instance_name']} events=#{events.join(',')}"
    rescue Custom::Whatsapp::EvolutionGo::ApiError => e
      failed += 1
      warn "[EVOLUTION_GO] sync failed channel=#{channel.id}: #{e.log_message}"
    end

    puts "[EVOLUTION_GO] sync_webhooks complete synced=#{synced} failed=#{failed}"
  end

  desc 'Repair Active Storage blobs corrupted by data-URL base64 decode (dry_run=1 to preview)'
  task repair_corrupt_media: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('dry_run', '0'))
    inbox_id = ENV['inbox_id'].presence
    limit = ENV.fetch('limit', '500').to_i

    channel_ids = Channel::Whatsapp.where(provider: 'evolution_go').pluck(:id)
    inbox_ids = Inbox.where(channel_type: 'Channel::Whatsapp', channel_id: channel_ids)
    inbox_ids = inbox_ids.where(id: inbox_id) if inbox_id
    inbox_ids = inbox_ids.pluck(:id)

    stats = { scanned: 0, repaired: 0, skipped: 0, failed: 0 }
    puts "[EVOLUTION_GO] repair_corrupt_media dry_run=#{dry_run} inboxes=#{inbox_ids.join(',')} limit=#{limit}"

    scope = Attachment.joins(:message, file_attachment: :blob)
                      .where(messages: { inbox_id: inbox_ids })
                      .order(id: :desc)
                      .limit(limit)

    scope.each do |attachment|
      stats[:scanned] += 1
      blob = attachment.file.blob
      bytes = blob.download
      unless Custom::Whatsapp::EvolutionGo::CorruptMediaRepair.corrupt_data_url_blob?(bytes)
        stats[:skipped] += 1
        next
      end

      if dry_run
        recovered = Custom::Whatsapp::EvolutionGo::CorruptMediaRepair.recover(bytes)
        puts "[EVOLUTION_GO] would_repair att=#{attachment.id} msg=#{attachment.message_id} " \
             "file=#{blob.filename} -> #{recovered&.dig(:mime_type)} bytes=#{recovered&.dig(:bytes)&.bytesize}"
        stats[:repaired] += 1
        next
      end

      result = Custom::Whatsapp::EvolutionGo::CorruptMediaRepairService.new(attachment: attachment).perform
      case result[:status]
      when :repaired
        stats[:repaired] += 1
        puts "[EVOLUTION_GO] repaired att=#{attachment.id} msg=#{attachment.message_id} #{result[:content_type]} #{result[:byte_size]}b"
      when :skipped
        stats[:skipped] += 1
      else
        stats[:failed] += 1
        warn "[EVOLUTION_GO] repair failed att=#{attachment.id}: #{result.inspect}"
      end
    end

    puts "[EVOLUTION_GO] repair_corrupt_media complete #{stats.inspect}"
  end

  desc 'Destroy leftover [Reaction message] placeholders (dry_run=1 default; set dry_run=0 to destroy)'
  task cleanup_reaction_placeholders: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('dry_run', '1'))
    limit = ENV.fetch('limit', '1000').to_i
    inbox_id = ENV['inbox_id'].presence

    channel_ids = Channel::Whatsapp.where(provider: %w[evolution_go evolution]).pluck(:id)
    inboxes = Inbox.where(channel_type: 'Channel::Whatsapp', channel_id: channel_ids)
    inboxes = inboxes.where(id: inbox_id) if inbox_id
    inbox_ids = inboxes.pluck(:id)

    messages = Message.where(inbox_id: inbox_ids, content: '[Reaction message]')
                      .order(id: :desc)
                      .limit(limit)
                      .to_a
    count = messages.size
    puts "[EVOLUTION_GO] cleanup_reaction_placeholders dry_run=#{dry_run} matched=#{count} limit=#{limit}"

    if dry_run
      messages.each { |m| puts "[EVOLUTION_GO] would_destroy message=#{m.id} inbox=#{m.inbox_id} conversation=#{m.conversation_id}" }
      puts "[EVOLUTION_GO] cleanup_reaction_placeholders dry_run complete count=#{count}"
      next
    end

    destroyed = 0
    messages.each do |message|
      message.destroy!
      destroyed += 1
      puts "[EVOLUTION_GO] destroyed message=#{message.id}"
    end
    puts "[EVOLUTION_GO] cleanup_reaction_placeholders complete destroyed=#{destroyed}"
  end
end
# rubocop:enable Metrics/BlockLength
