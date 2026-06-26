# frozen_string_literal: true

class Wavoip::Calls::RingEscalationScheduler
  def initialize(call:)
    @call = call
    @inbox = call.inbox
  end

  def schedule
    timeout = inbox.channel.ring_timeout_seconds
    return unless timeout.positive?

    lock_key = "wavoip:escalate_lock:#{call.id}"
    return if Rails.cache.read(lock_key)

    Rails.cache.write(lock_key, true, expires_in: (timeout + 5).seconds)
    Wavoip::EscalateRingJob.set(wait: timeout.seconds).perform_later(call.id)
  end

  private

  attr_reader :call, :inbox
end
