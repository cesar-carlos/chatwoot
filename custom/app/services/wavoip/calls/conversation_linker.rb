# frozen_string_literal: true

class Wavoip::Calls::ConversationLinker
  def self.link!(inbox:, event:)
    if event.direction == :outgoing
      new(inbox: inbox, event: event).link_outbound!
    else
      link_inbound!(inbox: inbox, event: event)
    end
  end

  def self.link_inbound!(inbox:, event:)
    extra_meta = build_meta(event)
    extra_meta['contact_name'] = event.peer_name if event.peer_name.present?

    Voice::InboundCallBuilder.perform!(
      inbox: inbox,
      from_number: contact_phone_for(event, inbox_phone: inbox.channel.phone_number),
      call_sid: event.external_call_id,
      provider: :wavoip,
      extra_meta: extra_meta
    )
  end

  def self.build_meta(event)
    {
      'wavoip_session_id' => event.session_id,
      'call_type' => event.call_type&.to_s,
      'wavoip_status' => event.external_status
    }.compact
  end

  def self.contact_phone_for(event, inbox_phone: nil)
    phone = event.from_phone.presence || event.to_phone
    Wavoip::PhoneNormalizer.normalize(phone, inbox_phone: inbox_phone)
  end

  def self.normalize_e164(phone, inbox_phone: nil)
    Wavoip::PhoneNormalizer.normalize(phone, inbox_phone: inbox_phone)
  end

  def initialize(inbox:, event:)
    @inbox = inbox
    @event = event
  end

  def link_outbound!
    existing = find_existing_call
    return existing if existing

    ActiveRecord::Base.transaction do
      contact_inbox = ensure_contact_inbox!
      contact = contact_inbox.contact
      conversation = resolve_conversation!(contact, contact_inbox)
      call = create_outgoing_call!(contact, conversation)
      message = Voice::CallMessageBuilder.new(call).perform!
      call.update!(message_id: message.id)
      call
    end
  rescue ActiveRecord::RecordNotUnique
    find_existing_call || raise
  end

  private

  attr_reader :inbox, :event

  def account
    inbox.account
  end

  def find_existing_call
    Call.find_by(
      account_id: account.id,
      inbox_id: inbox.id,
      provider: :wavoip,
      provider_call_id: event.external_call_id.to_s
    )
  end

  def contact_phone
    self.class.contact_phone_for(event, inbox_phone: inbox.channel.phone_number)
  end

  def ensure_contact_inbox!
    sid = contact_phone.delete_prefix('+')
    existing = inbox.contact_inboxes.find_by(source_id: sid)
    return existing if existing

    ContactInbox.create!(contact: ensure_contact!, inbox: inbox, source_id: sid)
  rescue ActiveRecord::RecordNotUnique
    inbox.contact_inboxes.find_by!(source_id: sid)
  end

  def ensure_contact!
    contact = account.contacts.find_or_create_by!(phone_number: contact_phone) do |record|
      record.name = event.peer_name.presence || contact_phone
    end
    contact.update!(name: event.peer_name) if event.peer_name.present? && contact.name == contact_phone
    contact
  end

  def resolve_conversation!(contact, contact_inbox)
    Conversations::Resolver.new(
      inbox: inbox,
      contact_inbox: contact_inbox,
      conversation_params: {
        account_id: account.id,
        inbox_id: inbox.id,
        contact_id: contact.id,
        contact_inbox_id: contact_inbox.id,
        status: :open
      }
    ).perform
  end

  def create_outgoing_call!(contact, conversation)
    Call.create!(
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: contact,
      provider: :wavoip,
      direction: :outgoing,
      status: 'ringing',
      provider_call_id: event.external_call_id.to_s,
      meta: self.class.build_meta(event).merge('initiated_at' => Time.zone.now.to_i)
    )
  end
end
