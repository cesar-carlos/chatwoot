# frozen_string_literal: true

# Caps how many contact enrichment jobs run at once so the low queue cannot
# monopolize Sidekiq workers / the DB pool (which delays WhatsappEventsJob).
module Custom::Whatsapp::ContactEnrichmentConcurrency
  extend ActiveSupport::Concern

  MAX_GLOBAL_IN_FLIGHT = 3
  GLOBAL_SLOT_TTL = 2.minutes.to_i
  GLOBAL_SLOT_RETRY_WAIT = 15.seconds
  GLOBAL_SLOT_KEY = 'CONTACT_ENRICHMENT_GLOBAL_IN_FLIGHT'

  private

  def with_global_enrichment_slot
    return retry_later_for_global_slot unless acquire_global_enrichment_slot!

    @global_slot_acquired = true
    yield
  ensure
    release_global_enrichment_slot! if @global_slot_acquired
  end

  def acquire_global_enrichment_slot!
    count = Redis::Alfred.incr(GLOBAL_SLOT_KEY)
    Redis::Alfred.expire(GLOBAL_SLOT_KEY, GLOBAL_SLOT_TTL) if count == 1
    return true if count <= MAX_GLOBAL_IN_FLIGHT

    Redis::Alfred.with { |conn| conn.decr(GLOBAL_SLOT_KEY) }
    false
  end

  def release_global_enrichment_slot!
    Redis::Alfred.with do |conn|
      value = conn.decr(GLOBAL_SLOT_KEY)
      conn.del(GLOBAL_SLOT_KEY) if value <= 0
    end
  end

  def retry_later_for_global_slot
    retry_job(wait: GLOBAL_SLOT_RETRY_WAIT)
  end
end
