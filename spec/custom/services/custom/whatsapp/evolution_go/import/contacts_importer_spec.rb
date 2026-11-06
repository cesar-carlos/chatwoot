# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::Import::ContactsImporter do
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
        'instance_token' => 'token',
        'import_contacts' => true,
        'import_messages' => false
      )
    )
  end
  let(:runtime) { Custom::Whatsapp::EvolutionGo::Import::Runtime.new(channel: channel) }
  let(:api_client) { instance_double(Custom::Whatsapp::EvolutionGo::ApiClient) }
  let(:importer) { described_class.new(runtime: runtime, api_client: api_client) }

  before do
    allow(Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob).to receive(:perform_later)
    Rails.cache.delete(runtime.contacts_cache_key)
  end

  def stub_contacts(records)
    response = instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => records })
    allow(api_client).to receive(:user_contacts).and_return(response)
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:raise_unless_success!)
  end

  it 'keeps a stored @lid and an agent-edited name, and skips status rows in the counter' do
    contact = create(
      :contact,
      account: account,
      phone_number: '+5511999999999',
      name: 'Nome do agente',
      additional_attributes: { 'evolution_go_remote_jid' => '999@lid' }
    )
    stub_contacts(
      [
        { 'Jid' => '5511999999999@s.whatsapp.net', 'PushName' => 'Agenda' },
        { 'Jid' => 'status@broadcast', 'PushName' => 'Status' }
      ]
    )

    importer.import_batch!

    contact.reload
    expect(contact.name).to eq('Nome do agente')
    expect(contact.additional_attributes['evolution_go_remote_jid']).to eq('999@lid')
    expect(channel.reload.provider_config.dig('import_stats', 'contacts_imported')).to eq(1)
  end

  it 'skips a contact whose phone is already taken and keeps importing the rest' do
    keeper = create(:contact, account: account, phone_number: '+14155552671', name: 'Keeper')
    keeper.errors.add(:phone_number, :taken)
    allow(keeper).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(keeper))
    locator = instance_double(Custom::Whatsapp::Import::ContactLocator)
    allow(locator).to receive(:find) { |phone| phone == '14155552671' ? keeper : nil }
    allow(Custom::Whatsapp::Import::ContactLocator).to receive(:new).and_return(locator)
    stub_contacts(
      [
        { 'Jid' => '14155552671@s.whatsapp.net', 'PushName' => 'Agenda' },
        { 'Jid' => '14155552672@s.whatsapp.net', 'PushName' => 'Next' }
      ]
    )

    expect { importer.import_batch! }.not_to raise_error

    expect(account.contacts.find_by(phone_number: '+14155552671')&.name).to eq('Keeper')
    expect(account.contacts.find_by(phone_number: '+14155552672')&.name).to eq('Next')
    expect(channel.reload.provider_config.dig('import_stats', 'contacts_imported')).to eq(1)
  end

  it 'attaches the address book row to the contact that already owns the canonical source id' do
    owner = create(:contact, account: account, phone_number: '+554399845097', name: 'Adelson Soeth')
    contact_inbox = create(
      :contact_inbox,
      contact: owner,
      inbox: channel.inbox,
      source_id: '5543999845097'
    )
    create(:contact, account: account, phone_number: '+5543999845097', name: 'Adelson Ghizoni Soethe')
    stub_contacts([{ 'Jid' => '554399845097@s.whatsapp.net', 'PushName' => 'Agenda Nova' }])

    expect { importer.import_batch! }.not_to raise_error

    expect(owner.reload.name).to eq('Adelson Soeth')
    expect(contact_inbox.reload.source_id).to eq('5543999845097')
    expect(contact_inbox.contact_id).to eq(owner.id)
    expect(account.contacts.where(phone_number: '+5543999845097').count).to eq(1)
    expect(channel.reload.provider_config.dig('import_stats', 'contacts_imported')).to eq(1)
  end

  it 'does not replace an identifier already stored on the contact' do
    contact = create(
      :contact,
      account: account,
      phone_number: '+5511888888888',
      name: 'Nome do agente',
      identifier: 'crm-1'
    )
    stub_contacts(
      [
        {
          'Jid' => '123@lid',
          'remoteJid' => '5511888888888@s.whatsapp.net',
          'PushName' => 'Agenda'
        }
      ]
    )

    importer.import_batch!

    expect(contact.reload.identifier).to eq('crm-1')
    expect(contact.name).to eq('Nome do agente')
    expect(channel.inbox.contact_inboxes.find_by(contact: contact, source_id: '5511888888888')).to be_present
  end

  it 'replaces a phone-number placeholder with the address-book push name' do
    contact = create(
      :contact,
      account: account,
      phone_number: '+5511999999999',
      name: '+5511999999999'
    )
    stub_contacts([{ 'Jid' => '5511999999999@s.whatsapp.net', 'PushName' => 'Agenda' }])

    importer.import_batch!

    expect(contact.reload.name).to eq('Agenda')
    expect(contact.additional_attributes['evolution_go_push_name']).to eq('Agenda')
  end
end
