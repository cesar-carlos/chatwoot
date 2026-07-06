# frozen_string_literal: true

class Custom::Whatsapp::Evolution::LostMessagesReconciliationJob < ApplicationJob
  queue_as :default

  retry_on MutexApplicationJob::LockAcquisitionError, wait: 5.seconds, attempts: 3

  THROTTLE_TTL = 30.minutes.to_i

  def perform
    evolution_channels_with_lost_sync.find_each do |channel|
      next unless throttle_claimed_for?(channel.id)

      Custom::Whatsapp::Evolution::LostMessagesReconciliationService.new(channel: channel).perform
    end
  end

  def evolution_channels_with_lost_sync
    Channel::Whatsapp.where(provider: 'evolution')
                     .where('provider_config @> ?', { sync_lost_messages: true }.to_json)
  end

  private

  def throttle_claimed_for?(channel_id)
    key = format(Redis::RedisKeys::EVOLUTION_LOST_MESSAGES_THROTTLE, channel_id: channel_id)
    ::Redis::Alfred.set(key, '1', nx: true, ex: THROTTLE_TTL)
  end
end
