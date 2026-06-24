# frozen_string_literal: true

class Custom::Whatsapp::Evolution::GroupContactService
  include Custom::Whatsapp::Evolution::GroupKeys

  pattr_initialize [:channel!, :remote_jid!, :push_name]

  def self.group_jid?(remote_jid)
    remote_jid.to_s.end_with?('@g.us')
  end

  def self.source_id_for(remote_jid)
    remote_jid.to_s
  end

  def find_or_create_contact_inbox!
    contact = find_or_create_group_contact!
    ContactInboxBuilder.new(
      contact: contact,
      inbox: inbox,
      source_id: self.class.source_id_for(remote_jid)
    ).perform
  end

  def contact_attributes
    {
      name: display_name,
      identifier: remote_jid,
      phone_number: nil,
      additional_attributes: {
        EVOLUTION_GROUP_JID_KEY => remote_jid,
        IS_WHATSAPP_GROUP_KEY => true
      }
    }
  end

  private

  def inbox
    channel.inbox
  end

  def account
    channel.account
  end

  def display_name
    Custom::Whatsapp::Evolution::GroupMetadataService.new(channel: channel)
                                                     .display_name(remote_jid, fallback: push_name)
  end

  def find_or_create_group_contact!
    contact = account.contacts.find_or_initialize_by(identifier: remote_jid)
    attrs = contact_attributes
    contact.name = attrs[:name] if contact.name.blank? || contact.name == remote_jid
    contact.identifier = remote_jid
    contact.phone_number = nil
    contact.additional_attributes = (contact.additional_attributes || {}).merge(attrs[:additional_attributes])
    contact.save!
    contact
  end
end
