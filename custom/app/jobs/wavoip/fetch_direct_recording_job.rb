# frozen_string_literal: true

# Fallback path for accounts whose Wavoip panel doesn't have the RECORD
# webhook enabled: poll the documented direct recording URL instead so the
# call history still gets a playable recording.
# https://wavoip.gitbook.io/api/gravacao
#
# Recordings can take a few minutes to become available after the call ends,
# so this retries a few times with a delay before giving up.
class Wavoip::FetchDirectRecordingJob < ApplicationJob
  queue_as :low

  INITIAL_DELAY = 2.minutes
  RETRY_DELAY = 3.minutes
  MAX_ATTEMPTS = 4
  # Only needs to cover one fetch attempt, and must not block this job's own
  # self-scheduled retries minutes later.
  LOCK_TTL = 1.minute

  def perform(call_id, attempt = 1)
    call = Call.find_by(id: call_id)
    return unless eligible?(call)
    return unless acquire_lock!(call_id)

    url = Wavoip::Calls::DirectRecordingUrl.for(call)
    return if url.blank?

    Wavoip::Calls::RecordingAttachmentService.new(
      call: call,
      record_url: url,
      store_fallback_on_error: false
    ).perform

    retry_later(call_id, attempt) unless call.reload.recording.attached?
  end

  private

  def eligible?(call)
    return false if call.blank?
    return false unless call.wavoip?
    return false unless call.status == 'completed'
    return false if call.recording.attached?
    return false if blocked_by_known_status?(call)

    true
  end

  def blocked_by_known_status?(call)
    status = call.meta&.dig('record_status').to_s.upcase
    Wavoip::Calls::RecordingPolicy::BLOCKED_STATUSES.include?(status)
  end

  # A single call can have this job scheduled more than once for the exact
  # same attempt (e.g. two ENDED webhooks racing into CallStatusApplier) —
  # dedupe concurrent executions so two workers don't fetch and attach the
  # same recording at once.
  def acquire_lock!(call_id)
    Rails.cache.write(
      "wavoip:direct_recording_lock:#{call_id}", true, unless_exist: true, expires_in: LOCK_TTL
    )
  end

  def retry_later(call_id, attempt)
    return if attempt >= MAX_ATTEMPTS

    self.class.set(wait: RETRY_DELAY).perform_later(call_id, attempt + 1)
  end
end
