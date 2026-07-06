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
    allow(Custom::Whatsapp::Evolution::ContactEnrichmentJob).to receive(:perform_later)
  end

  describe '#perform' do
    it 'imports contacts and advances cursor' do
      allow(api_client).to receive(:find_contacts).and_return(
        instance_double(
          HTTParty::Response,
          success?: true,
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

    it 'enqueues contact enrichment with profile picture during import' do
      allow(api_client).to receive(:find_contacts).and_return(
        instance_double(
          HTTParty::Response,
          success?: true,
          parsed_response: [
            {
              'remoteJid' => '5511999999999@s.whatsapp.net',
              'pushName' => 'Alice',
              'profilePictureUrl' => 'https://pps.whatsapp.net/v/alice.jpg'
            }
          ]
        )
      )

      service.perform

      contact = account.contacts.find_by(phone_number: '+5511999999999')
      expect(Custom::Whatsapp::Evolution::ContactEnrichmentJob).to have_received(:perform_later).with(
        channel.id,
        contact.id,
        hash_including(
          profile_pic_url: 'https://pps.whatsapp.net/v/alice.jpg',
          force: true
        )
      )
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

    it 'skips import when another worker holds the Redis lock' do
      lock_key = format(Redis::RedisKeys::EVOLUTION_IMPORT_LOCK, channel_id: channel.id)
      Redis::Alfred.set(lock_key, true, nx: true, ex: described_class::IMPORT_LOCK_TTL)

      expect(api_client).not_to receive(:find_contacts)
      service.perform
    ensure
      Redis::Alfred.delete(lock_key)
    end

    it 'skips a fresh "running" import without force (no stale heartbeat)' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'import_status' => 'running',
          'import_started_at' => 5.minutes.ago.iso8601,
          'import_heartbeat_at' => 1.minute.ago.iso8601
        )
      )

      expect(api_client).not_to receive(:find_contacts)
      described_class.new(channel: channel.reload).perform
    end

    it 'resumes an import stuck as "running" once its heartbeat goes stale (crash recovery)' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'import_status' => 'running',
          'import_started_at' => 3.hours.ago.iso8601,
          'import_heartbeat_at' => 3.hours.ago.iso8601,
          'import_cursor' => { 'phase' => 'contacts', 'contacts_page' => 1 }
        )
      )
      allow(api_client).to receive(:find_contacts).and_return(
        instance_double(
          HTTParty::Response,
          success?: true,
          parsed_response: [
            { 'remoteJid' => '5511999999999@s.whatsapp.net', 'pushName' => 'Alice' }
          ]
        )
      )

      described_class.new(channel: channel.reload).perform

      channel.reload
      expect(channel.provider_config['import_status']).to eq('completed')
      expect(account.contacts.find_by(phone_number: '+5511999999999')).to be_present
    end

    it 'marks import_failed_at and releases the import lock when import raises' do
      lock_key = format(Redis::RedisKeys::EVOLUTION_IMPORT_LOCK, channel_id: channel.id)
      allow(api_client).to receive(:find_contacts).and_raise(StandardError, 'import boom')

      service.perform

      channel.reload
      expect(channel.provider_config['import_status']).to eq('failed')
      expect(channel.provider_config['import_failed_at']).to be_present
      expect(channel.provider_config['import_completed_at']).to be_nil
      expect(Redis::Alfred.get(lock_key)).to be_nil
    end
  end
end
