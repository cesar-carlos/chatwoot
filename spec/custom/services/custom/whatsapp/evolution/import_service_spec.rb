# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::ImportService do
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
        'api_key' => 'TEST-INSTANCE-API-KEY',
        'import_contacts' => true,
        'import_messages' => false
      )
    )
  end
  let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }
  let(:service) { described_class.new(channel: channel) }

  before do
    create(:inbox, account: account, channel: channel)
    allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:new).and_return(api_client)
  end

  describe '#perform' do
    it 'imports contacts and advances cursor' do
      allow(api_client).to receive(:find_contacts).and_return(
        instance_double(
          HTTParty::Response,
          parsed_response: [
            { 'remoteJid' => '5511999999999@s.whatsapp.net', 'pushName' => 'Alice' }
          ]
        )
      )

      service.perform

      channel.reload
      expect(channel.provider_config['import_status']).to eq('completed')
      expect(channel.provider_config['import_stats']['contacts_imported']).to eq(1)
      expect(account.contacts.find_by(phone_number: '+5511999999999')).to be_present
    end

    it 'skips when import flags are disabled' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'import_contacts' => false,
          'import_messages' => false
        )
      )

      expect(api_client).not_to receive(:find_contacts)
      described_class.new(channel: channel.reload).perform
    end
  end
end
