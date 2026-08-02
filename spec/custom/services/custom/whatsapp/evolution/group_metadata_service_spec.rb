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

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)
    Rails.cache.clear
    example.run
    Rails.cache = original_cache
  end

  before do
    allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:for_channel).with(channel).and_return(api_client)
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

    it 'does not use Evolution Go client (no group avatar path) on evolution channels' do
      allow(api_client).to receive(:find_group_infos).with(group_jid: group_jid).and_return(
        instance_double(HTTParty::Response, success?: true, parsed_response: fixture)
      )
      expect(Custom::Whatsapp::EvolutionGo::ApiClient).not_to receive(:for_channel)

      expect(service.warm_cache!(group_jid)).to eq('Support Team (GROUP)')
    end

    it 'returns nil when API fails' do
      allow(api_client).to receive(:find_group_infos).and_raise(Custom::Whatsapp::Evolution::ApiError.new('fail'))

      expect(service.warm_cache!(group_jid)).to be_nil
    end
  end

  describe '#warm_cache! with evolution_go' do
    let(:channel) do
      create(
        :channel_whatsapp,
        account: account,
        provider: 'evolution_go',
        sync_templates: false,
        validate_provider_config: false,
        provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
          'instance_name' => 'test-instance',
          'instance_token' => 'INSTANCE-TOKEN'
        )
      )
    end
    let(:go_api_client) { instance_double(Custom::Whatsapp::EvolutionGo::ApiClient) }
    let(:group_info_payload) do
      {
        'success' => true,
        'data' => {
          'JID' => group_jid,
          'Name' => 'Support Team'
        }
      }
    end

    before do
      allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).with(channel).and_return(go_api_client)
      create(
        :contact,
        account: account,
        identifier: group_jid,
        name: group_jid,
        additional_attributes: {
          Custom::Whatsapp::Evolution::GroupKeys::IS_WHATSAPP_GROUP_KEY => true,
          Custom::Whatsapp::Evolution::GroupKeys::EVOLUTION_GROUP_JID_KEY => group_jid
        }
      )
    end

    it 'syncs name and enqueues avatar download from /user/avatar with group JID' do
      allow(go_api_client).to receive(:group_info).with(group_jid: group_jid).and_return(
        instance_double(HTTParty::Response, success?: true, parsed_response: group_info_payload)
      )
      allow(go_api_client).to receive(:user_avatar).with(number: group_jid, preview: true).and_return(
        instance_double(
          HTTParty::Response,
          success?: true,
          parsed_response: { 'data' => { 'url' => 'https://cdn.example.com/group-avatar.jpg' } }
        )
      )

      contact = account.contacts.find_by!(identifier: group_jid)

      expect do
        expect(service.warm_cache!(group_jid)).to eq('Support Team (GROUP)')
      end.to have_enqueued_job(Avatar::AvatarFromUrlJob).with(contact, 'https://cdn.example.com/group-avatar.jpg')

      expect(contact.reload.name).to eq('Support Team (GROUP)')
    end

    it 'still syncs name when group has no profile picture' do
      allow(go_api_client).to receive(:group_info).with(group_jid: group_jid).and_return(
        instance_double(HTTParty::Response, success?: true, parsed_response: group_info_payload)
      )
      allow(go_api_client).to receive(:user_avatar).with(number: group_jid, preview: true).and_return(
        instance_double(
          HTTParty::Response,
          success?: false,
          code: 500,
          parsed_response: { 'error' => 'that user or group does not have a profile picture' }
        )
      )

      expect do
        expect(service.warm_cache!(group_jid)).to eq('Support Team (GROUP)')
      end.not_to have_enqueued_job(Avatar::AvatarFromUrlJob)

      expect(account.contacts.find_by!(identifier: group_jid).reload.name).to eq('Support Team (GROUP)')
      expect(account.contacts.find_by!(identifier: group_jid).avatar).not_to be_attached
    end

    it 'warms cache from an inline subject without calling group_info' do
      expect(go_api_client).not_to receive(:group_info)
      allow(go_api_client).to receive(:user_avatar).with(number: group_jid, preview: true).and_return(
        instance_double(HTTParty::Response, success?: false, code: 500, parsed_response: {})
      )

      expect(service.warm_cache_from_name!(group_jid, 'NortAgro Suporte')).to eq('NortAgro Suporte (GROUP)')
      expect(Rails.cache.read("evolution:group_metadata:#{channel.id}:#{group_jid}")).to eq('NortAgro Suporte (GROUP)')
      expect(account.contacts.find_by!(identifier: group_jid).reload.name).to eq('NortAgro Suporte (GROUP)')
    end

    it 'force-refreshes an existing group avatar on API warm_cache!' do
      contact = account.contacts.find_by!(identifier: group_jid)
      contact.avatar.attach(
        io: StringIO.new('old-avatar'),
        filename: 'old.png',
        content_type: 'image/png'
      )
      expect(contact.avatar).to be_attached

      allow(go_api_client).to receive(:group_info).with(group_jid: group_jid).and_return(
        instance_double(HTTParty::Response, success?: true, parsed_response: group_info_payload)
      )
      allow(go_api_client).to receive(:user_avatar).with(number: group_jid, preview: true).and_return(
        instance_double(
          HTTParty::Response,
          success?: true,
          parsed_response: { 'data' => { 'url' => 'https://cdn.example.com/group-avatar-new.jpg' } }
        )
      )

      expect do
        expect(service.warm_cache!(group_jid)).to eq('Support Team (GROUP)')
      end.to have_enqueued_job(Avatar::AvatarFromUrlJob)
        .with(contact, 'https://cdn.example.com/group-avatar-new.jpg')

      expect(contact.reload.avatar).not_to be_attached
    end

    it 'does not purge existing avatar on inline warm without force' do
      contact = account.contacts.find_by!(identifier: group_jid)
      contact.avatar.attach(
        io: StringIO.new('old-avatar'),
        filename: 'old.png',
        content_type: 'image/png'
      )

      expect(go_api_client).not_to receive(:user_avatar)

      service.warm_cache_from_name!(group_jid, 'Keep Avatar')

      expect(contact.reload.avatar).to be_attached
    end
  end
end
