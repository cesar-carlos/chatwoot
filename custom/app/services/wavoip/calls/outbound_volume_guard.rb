# frozen_string_literal: true

# Soft ops guardrail: Redis daily counter of outbound Wavoip call creates per account.
# Does not block calls — only returns a warn level and logs at threshold crossings.
class Wavoip::Calls::OutboundVolumeGuard
  SOFT_THRESHOLD = 20
  ELEVATED_THRESHOLD = 50
  KEY_TTL = 2.days.to_i

  def self.increment_and_warn_level(account_id)
    new(account_id).increment_and_warn_level
  end

  def initialize(account_id)
    @account_id = account_id
  end

  def increment_and_warn_level
    count = Redis::Alfred.incr(redis_key)
    Redis::Alfred.expire(redis_key, KEY_TTL) if count == 1
    log_threshold_crossing(count)
    level_for(count)
  end

  private

  attr_reader :account_id

  def redis_key
    "WAVOIP::OUTBOUND_VOLUME::#{account_id}::#{Time.zone.today.iso8601}"
  end

  def level_for(count)
    return :elevated if count >= ELEVATED_THRESHOLD
    return :soft if count >= SOFT_THRESHOLD

    :none
  end

  def log_threshold_crossing(count)
    return unless count == SOFT_THRESHOLD || count == ELEVATED_THRESHOLD

    Rails.logger.warn(
      "[WAVOIP] outbound volume account_id=#{account_id} count=#{count} level=#{level_for(count)}"
    )
  end
end
