# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::GroupMetadataService do
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
  let(:group_jid) { '120363123456789012@g.us' }
  let(:service) { described_class.new(channel: channel) }
  let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/evolution/group_find_infos_response.json').read) }

  before do
    allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:for_channel).with(channel).and_return(api_client)
    Rails.cache.clear
  end

  describe '#display_name' do
    it 'returns subject with (GROUP) suffix from API' do
      allow(api_client).to receive(:find_group_infos).with(group_jid: group_jid).and_return(
        instance_double(HTTParty::Response, success?: true, parsed_response: fixture)
      )

      expect(service.display_name(group_jid, fallback: 'Member')).to eq('Support Team (GROUP)')
    end

    it 'caches the resolved name' do
      allow(Rails.cache).to receive(:read).and_return(nil, 'Support Team (GROUP)')
      allow(Rails.cache).to receive(:write)
      allow(api_client).to receive(:find_group_infos).and_return(
        instance_double(HTTParty::Response, success?: true, parsed_response: fixture)
      )

      2.times { service.display_name(group_jid) }

      expect(api_client).to have_received(:find_group_infos).once
    end

    it 'falls back to push name when API fails' do
      allow(api_client).to receive(:find_group_infos).and_raise(Custom::Whatsapp::Evolution::ApiError.new('fail'))

      expect(service.display_name(group_jid, fallback: 'Member')).to eq('Member')
    end
  end
end
