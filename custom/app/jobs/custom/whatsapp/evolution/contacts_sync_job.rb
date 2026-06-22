# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ContactsSyncJob < ApplicationJob
  queue_as :low

  def perform(channel_id, data)
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution')
    return if channel.blank?

    Custom::Whatsapp::Evolution::ContactsSyncService.new(channel: channel, data: data).perform
  end
end
