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
