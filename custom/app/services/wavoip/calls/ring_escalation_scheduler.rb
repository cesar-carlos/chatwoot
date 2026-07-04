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
    # `unless_exist` makes the read+write atomic (SETNX on Redis) — two
    # concurrent webhook retries racing here can no longer both enqueue a job.
    acquired = Rails.cache.write(lock_key, true, unless_exist: true, expires_in: (timeout + 5).seconds)
    return unless acquired

    Wavoip::EscalateRingJob.set(wait: timeout.seconds).perform_later(call.id)
  end

  private

  attr_reader :call, :inbox
end
