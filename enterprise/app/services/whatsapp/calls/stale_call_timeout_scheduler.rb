# frozen_string_literal: true

# Meta only signals call end via webhook. If that webhook is dropped, the Call
# row stays ringing and resurfaces as a ghost widget on every hydrate.
class Whatsapp::Calls::StaleCallTimeoutScheduler
  DEFAULT_RINGING_TIMEOUT_SECONDS = 120

  def initialize(call:)
    @call = call
  end

  def schedule
    lock_key = "whatsapp:stale_ring_lock:#{call.id}"
    acquired = Rails.cache.write(lock_key, true, unless_exist: true, expires_in: (timeout_seconds + 30).seconds)
    return unless acquired

    Whatsapp::AutoNoAnswerRingJob.set(wait: timeout_seconds.seconds).perform_later(call.id)
  end

  def schedule_in_progress_safety_net
    lock_key = "whatsapp:stale_progress_lock:#{call.id}"
    acquired = Rails.cache.write(lock_key, true, unless_exist: true, expires_in: (in_progress_timeout_seconds + 60).seconds)
    return unless acquired

    Whatsapp::StaleInProgressCallJob.set(wait: in_progress_timeout_seconds.seconds).perform_later(call.id)
  end

  private

  attr_reader :call

  def timeout_seconds
    DEFAULT_RINGING_TIMEOUT_SECONDS * 2
  end

  def in_progress_timeout_seconds
    2.hours.to_i
  end
end
