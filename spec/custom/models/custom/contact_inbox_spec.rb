# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ContactInbox do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def whatsapp_inbox(provider:)
    create(
      :channel_whatsapp,
      account: account,
      provider: provider,
      sync_templates: false,
      validate_provider_config: false
    ).inbox
  end

  it 'allows @lid source_id on evolution_go inboxes' do
    inbox = whatsapp_inbox(provider: 'evolution_go')
    contact_inbox = build(:contact_inbox, contact: contact, inbox: inbox, source_id: '123456789012345@lid')

    expect(contact_inbox).to be_valid
    expect { contact_inbox.save! }.not_to raise_error
  end

  it 'allows @g.us source_id on evolution_go inboxes' do
    inbox = whatsapp_inbox(provider: 'evolution_go')
    contact_inbox = build(:contact_inbox, contact: contact, inbox: inbox, source_id: '120363012345678901@g.us')

    expect(contact_inbox).to be_valid
  end

  it 'rejects @lid source_id on non-evolution_go whatsapp inboxes' do
    inbox = whatsapp_inbox(provider: 'whatsapp_cloud')
    contact_inbox = build(:contact_inbox, contact: contact, inbox: inbox, source_id: '123456789012345@lid')

    expect(contact_inbox).not_to be_valid
  end
end
