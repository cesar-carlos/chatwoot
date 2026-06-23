# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::ContactsSyncService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'instance_name' => 'test-instance',
        'api_key' => 'TEST-KEY'
      )
    )
  end

  before do
    allow(Custom::Whatsapp::Evolution::ContactEnrichmentJob).to receive(:perform_later)
  end

  it 'creates contact and enqueues enrichment from CONTACTS_UPSERT payload' do
    described_class.new(
      channel: channel,
      data: {
        'remoteJid' => '556696971841@s.whatsapp.net',
        'pushName' => 'Matheus Teixeira',
        'profilePicUrl' => 'https://pps.whatsapp.net/v/example.jpg'
      }
    ).perform

    contact = account.contacts.find_by(phone_number: '+5566996971841')
    expect(contact).to be_present
    expect(contact.name).to eq('Matheus Teixeira')
    expect(Custom::Whatsapp::Evolution::ContactEnrichmentJob).to have_received(:perform_later).with(
      channel.id,
      contact.id,
      hash_including(
        remote_jid: '556696971841@s.whatsapp.net',
        push_name: 'Matheus Teixeira',
        profile_pic_url: 'https://pps.whatsapp.net/v/example.jpg'
      )
    )
  end

  it 'skips group contacts when groups_ignore is enabled' do
    described_class.new(
      channel: channel,
      data: { 'remoteJid' => '120363123456789012@g.us', 'pushName' => 'Group' }
    ).perform

    expect(account.contacts.count).to eq(0)
    expect(Custom::Whatsapp::Evolution::ContactEnrichmentJob).not_to have_received(:perform_later)
  end

  it 'skips redundant enrichment jobs when the contact was enriched recently with the same payload' do
    contact = create(
      :contact,
      account: account,
      name: 'Matheus Teixeira',
      phone_number: '+5566996971841',
      additional_attributes: {
        'evolution_remote_jid' => '556696971841@s.whatsapp.net',
        'evolution_push_name' => 'Matheus Teixeira',
        'evolution_enriched_at' => Time.current.utc.iso8601(3)
      }
    )
    create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '5566996971841')

    described_class.new(
      channel: channel,
      data: {
        'remoteJid' => '556696971841@s.whatsapp.net',
        'pushName' => 'Matheus Teixeira'
      }
    ).perform

    expect(Custom::Whatsapp::Evolution::ContactEnrichmentJob).not_to have_received(:perform_later)
  end
end
