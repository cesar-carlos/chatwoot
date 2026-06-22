# frozen_string_literal: true

class Custom::Whatsapp::Evolution::LostMessagesReconciliationJob < ApplicationJob
  queue_as :low

  THROTTLE_KEY = 'evolution:lost_messages_reconciliation'
  THROTTLE_TTL = 30.minutes

  def perform
    return unless throttle_claimed?

    evolution_channels_with_lost_sync.find_each do |channel|
      Custom::Whatsapp::Evolution::LostMessagesReconciliationService.new(channel: channel).perform
    end
  end

  def evolution_channels_with_lost_sync
    Channel::Whatsapp.where(provider: 'evolution')
                     .where('provider_config @> ?', { sync_lost_messages: true }.to_json)
  end

  private

  def throttle_claimed?
    Redis::Alfred.set(THROTTLE_KEY, '1', nx: true, ex: THROTTLE_TTL.to_i)
  end
end
