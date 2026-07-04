# frozen_string_literal: true

# Wavoip only tells us a call ended via webhook. If that webhook is dropped
# (or the agent's SDK session ends the call locally without one), the Call
# row is stuck "ringing" forever and keeps resurfacing as a ghost widget.
# Schedule a safety-net job that force-closes it as +no_answer+ well past any
# realistic ring/escalation window.
class Wavoip::Calls::StaleCallTimeoutScheduler
  DEFAULT_TIMEOUT_SECONDS = 90

  def initialize(call:)
    @call = call
    @inbox = call.inbox
  end

  def schedule
    lock_key = "wavoip:stale_ring_lock:#{call.id}"
    # `unless_exist` makes the read+write atomic (SETNX on Redis) — concurrent
    # webhook retries racing here can no longer both enqueue a job.
    acquired = Rails.cache.write(lock_key, true, unless_exist: true, expires_in: (timeout_seconds + 30).seconds)
    return unless acquired

    Wavoip::AutoNoAnswerRingJob.set(wait: timeout_seconds.seconds).perform_later(call.id)
  end

  private

  attr_reader :call, :inbox

  def timeout_seconds
    return inbox.channel.outbound_stale_timeout_seconds if call.outgoing?

    configured = inbox.channel.ring_timeout_seconds
    base = configured.positive? ? configured : DEFAULT_TIMEOUT_SECONDS
    base * 2
  end
end
