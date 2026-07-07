# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::ImportJob < ApplicationJob
  queue_as :low

  def perform(channel_id, force: false)
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution_go')
    return if channel.blank?

    Custom::Whatsapp::EvolutionGo::ImportService.new(channel: channel, force: force).perform
  end
end
