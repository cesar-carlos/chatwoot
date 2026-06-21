# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ImportJob < ApplicationJob
  queue_as :low

  def perform(channel_id, force: false)
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution')
    return if channel.blank?

    Custom::Whatsapp::Evolution::ImportService.new(channel: channel, force: force).perform
  end
end
