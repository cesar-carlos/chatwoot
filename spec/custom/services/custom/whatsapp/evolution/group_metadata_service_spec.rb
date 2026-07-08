# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::GroupMetadataService do
  include ActiveJob::TestHelper

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
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)
    Rails.cache.clear
  end

  after do
    Rails.cache = @previous_cache
  end

  describe '#display_name' do
    it 'returns fallback and enqueues async fetch on cache miss' do
      expect(api_client).not_to receive(:find_group_infos)

      expect do
        expect(service.display_name(group_jid, fallback: 'Member')).to eq('Member')
      end.to have_enqueued_job(Custom::Whatsapp::Evolution::GroupMetadataFetchJob)
        .with(channel.id, group_jid)
    end

    it 'returns cached name without enqueueing another fetch' do
      Rails.cache.write(
        "evolution:group_metadata:#{channel.id}:#{group_jid}",
        'Support Team (GROUP)',
        expires_in: 1.hour
      )

      expect do
        expect(service.display_name(group_jid, fallback: 'Member')).to eq('Support Team (GROUP)')
      end.not_to have_enqueued_job(Custom::Whatsapp::Evolution::GroupMetadataFetchJob)
    end

    it 'falls back to jid prefix when fallback is blank' do
      expect(service.display_name(group_jid)).to eq('120363123456789012')
    end

    it 'enqueues only one fetch job per group while the enqueue lock is held' do
      expect do
        2.times { service.display_name(group_jid, fallback: 'Member') }
      end.to have_enqueued_job(Custom::Whatsapp::Evolution::GroupMetadataFetchJob).exactly(:once)
    end
  end

  describe '#warm_cache!' do
    it 'fetches group subject from API and caches the display name' do
      allow(api_client).to receive(:find_group_infos).with(group_jid: group_jid).and_return(
        instance_double(HTTParty::Response, success?: true, parsed_response: fixture)
      )

      expect(service.warm_cache!(group_jid)).to eq('Support Team (GROUP)')
      expect(
        Rails.cache.read("evolution:group_metadata:#{channel.id}:#{group_jid}")
      ).to eq('Support Team (GROUP)')
    end

    it 'returns nil when API fails' do
      allow(api_client).to receive(:find_group_infos).and_raise(Custom::Whatsapp::Evolution::ApiError.new('fail'))

      expect(service.warm_cache!(group_jid)).to be_nil
    end
  end
end
