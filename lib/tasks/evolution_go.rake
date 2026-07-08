# frozen_string_literal: true

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
end
