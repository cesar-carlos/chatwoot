# frozen_string_literal: true

class Custom::Whatsapp::Evolution::GroupMetadataFetchJob < ApplicationJob
  queue_as :low

  SUPPORTED_PROVIDERS = Custom::Whatsapp::Evolution::GroupMetadataService::SUPPORTED_PROVIDERS

  def perform(channel_id, group_jid)
    channel = Channel::Whatsapp.find_by(id: channel_id)
    return if channel.blank? || group_jid.blank?
    return unless channel.provider.in?(SUPPORTED_PROVIDERS)

    Custom::Whatsapp::Evolution::GroupMetadataService.new(channel: channel).warm_cache!(group_jid)
  end
end
