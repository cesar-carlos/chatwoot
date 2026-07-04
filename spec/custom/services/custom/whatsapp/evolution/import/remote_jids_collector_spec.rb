# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::Import::RemoteJidsCollector do
  subject(:collector) do
    described_class.new(runtime: runtime, api_client: api_client)
  end

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
        'api_key' => 'TEST-KEY',
        'base_url' => 'http://localhost:8080',
        'groups_ignore' => true,
        'ignore_status_broadcast' => true
      )
    )
  end
  let(:runtime) { Custom::Whatsapp::Evolution::Import::Runtime.new(channel: channel) }
  let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }

  before do
    create(:inbox, account: account, channel: channel)
  end

  describe '#collect!' do
    it 'returns direct chat jids and skips groups and status broadcast' do
      allow(api_client).to receive(:find_contacts).and_return(
        instance_double(
          HTTParty::Response,
          success?: true,
          parsed_response: [
            { 'remoteJid' => '5511999999999@s.whatsapp.net' },
            { 'remoteJid' => '120363123456789012@g.us' },
            { 'remoteJid' => 'status@broadcast' },
            { 'remoteJid' => '5511888888888@s.whatsapp.net' }
          ]
        )
      )

      expect(collector.collect!).to eq(
        %w[5511999999999@s.whatsapp.net 5511888888888@s.whatsapp.net]
      )
    end

    it 'parses the nested { contacts: { records: [...] } } response shape' do
      allow(api_client).to receive(:find_contacts).and_return(
        instance_double(
          HTTParty::Response,
          success?: true,
          parsed_response: {
            'contacts' => {
              'records' => [
                { 'remoteJid' => '5511999999999@s.whatsapp.net' },
                { 'remoteJid' => '120363123456789012@g.us' }
              ]
            }
          }
        )
      )

      expect(collector.collect!).to eq(%w[5511999999999@s.whatsapp.net])
    end

    it 'includes group jids when groups_ignore is false' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'groups_ignore' => false,
          'ignore_jids' => []
        )
      )

      allow(api_client).to receive(:find_contacts).and_return(
        instance_double(
          HTTParty::Response,
          success?: true,
          parsed_response: [
            { 'remoteJid' => '120363123456789012@g.us' },
            { 'remoteJid' => '5511999999999@s.whatsapp.net' }
          ]
        )
      )

      expect(collector.collect!).to eq(
        %w[120363123456789012@g.us 5511999999999@s.whatsapp.net]
      )
    end
  end
end
