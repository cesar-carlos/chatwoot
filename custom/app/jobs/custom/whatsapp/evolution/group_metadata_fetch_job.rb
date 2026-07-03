# frozen_string_literal: true

class Custom::Whatsapp::Evolution::GroupMetadataFetchJob < ApplicationJob
  queue_as :low

  def perform(channel_id, group_jid)
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution')
    return if channel.blank? || group_jid.blank?

    Custom::Whatsapp::Evolution::GroupMetadataService.new(channel: channel).warm_cache!(group_jid)
  end
end
