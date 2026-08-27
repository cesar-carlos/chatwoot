# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::PeerContactInboxResolver do
  subject(:resolver) { described_class.new(channel: channel, key: key) }

  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_name' => 'test-go-instance',
        'instance_token' => 'token'
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:key) do
    {
      'id' => 'PHONE-SENT-001',
      'fromMe' => true,
      'remoteJid' => '123456789012345@lid',
      'remoteJidAlt' => '556696971841@s.whatsapp.net',
      'addressingMode' => 'lid'
    }
  end

  it 'reuses an existing contact inbox matched by evolution_go_remote_jid' do
    contact = create(
      :contact,
      account: account,
      phone_number: '+556696971841',
      additional_attributes: {
        Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY =>
          '123456789012345@lid'
      }
    )
    existing = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566996971841')

    expect(resolver.find_or_create!).to eq(existing)
    expect(ContactInbox.where(inbox: inbox).count).to eq(1)
  end

  it 'reuses an existing contact inbox matched by source_id' do
    contact = create(:contact, account: account, phone_number: '+556696971841')
    existing = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566996971841')

    key['remoteJid'] = '556696971841@s.whatsapp.net'
    key.delete('remoteJidAlt')

    expect(resolver.find_or_create!).to eq(existing)
  end

  it 'creates a contact inbox for a new peer' do
    key['remoteJid'] = '5566999999999@s.whatsapp.net'
    key.delete('remoteJidAlt')

    expect { resolver.find_or_create! }.to change(ContactInbox, :count).by(1)

    contact_inbox = ContactInbox.last
    expect(contact_inbox.source_id).to eq('5566999999999')
    expect(contact_inbox.contact.phone_number).to eq('+5566999999999')
  end

  it 'creates a LID-only contact without fabricating a phone number' do
    key.delete('remoteJidAlt')

    expect { resolver.find_or_create! }.to change(ContactInbox, :count).by(1)

    contact_inbox = ContactInbox.last
    expect(contact_inbox.source_id).to eq('123456789012345@lid')
    expect(contact_inbox.contact.identifier).to eq('123456789012345@lid')
    expect(contact_inbox.contact.phone_number).to be_nil
    expect(contact_inbox.contact.additional_attributes['evolution_go_remote_jid']).to eq('123456789012345@lid')
  end

  it 'reuses a phone contact_inbox for LID+alt and stamps identifier' do
    contact = create(:contact, account: account, phone_number: '+556696971841')
    existing = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566996971841')

    expect(resolver.find_or_create!).to eq(existing)
    expect(ContactInbox.where(inbox: inbox).count).to eq(1)

    contact.reload
    expect(contact.identifier).to eq('123456789012345@lid')
    expect(contact.additional_attributes['evolution_go_remote_jid']).to eq('123456789012345@lid')
  end
end
