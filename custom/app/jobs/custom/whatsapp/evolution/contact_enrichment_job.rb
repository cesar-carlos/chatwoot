# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ContactEnrichmentJob < ApplicationJob
  queue_as :low

  def perform(channel_id, contact_id, attrs = {})
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution')
    contact = Contact.find_by(id: contact_id)
    return if channel.blank? || contact.blank?

    attrs = attrs.with_indifferent_access
    Custom::Whatsapp::Evolution::ContactEnrichmentService.new(
      channel: channel,
      contact: contact,
      remote_jid: attrs[:remote_jid],
      push_name: attrs[:push_name],
      profile_pic_url: attrs[:profile_pic_url]
    ).perform
  end
end
