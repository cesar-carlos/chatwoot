# frozen_string_literal: true

# Clears the contacts-refresh lock after paced enrichment should have finished.
# Redis TTL is the safety net; this job frees the lock on schedule so the UI
# can allow another refresh without waiting for a long idle TTL.
class Custom::Whatsapp::EvolutionGo::ContactsRefreshLockReleaseJob < ApplicationJob
  queue_as :low

  def perform(channel_id)
    Custom::Whatsapp::EvolutionGo::ContactsRefreshService.release_lock!(channel_id)
  end
end
