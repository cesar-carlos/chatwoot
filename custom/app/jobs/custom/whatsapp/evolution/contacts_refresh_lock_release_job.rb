# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ContactsRefreshLockReleaseJob < ApplicationJob
  queue_as :low

  def perform(channel_id)
    Custom::Whatsapp::Evolution::ContactsRefreshService.release_lock!(channel_id)
  end
end
