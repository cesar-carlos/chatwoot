# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::ContactEnrichmentJob do
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
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:enrichment_service) { instance_double(Custom::Whatsapp::Evolution::ContactEnrichmentService, perform: nil) }

  before do
    allow(Custom::Whatsapp::Evolution::ContactEnrichmentService).to receive(:new).and_return(enrichment_service)
    allow(Custom::Whatsapp::Evolution::ContactEnrichmentService).to receive(:enrichment_stale?).and_return(true)
    Redis::Alfred.delete(format(Redis::RedisKeys::EVOLUTION_CONTACT_ENRICHMENT, contact_id: contact.id))
  end

  describe '#perform' do
    it 'runs enrichment and releases the in-flight lock' do
      described_class.perform_now(channel.id, contact.id, remote_jid: '5511999999999@s.whatsapp.net')

      expect(enrichment_service).to have_received(:perform)
      lock_key = format(Redis::RedisKeys::EVOLUTION_CONTACT_ENRICHMENT, contact_id: contact.id)
      expect(Redis::Alfred.get(lock_key)).to be_nil
    end

    it 'skips when lock is already held' do
      lock_key = format(Redis::RedisKeys::EVOLUTION_CONTACT_ENRICHMENT, contact_id: contact.id)
      Redis::Alfred.set(lock_key, true, nx: true, ex: 120)

      described_class.perform_now(channel.id, contact.id, remote_jid: '5511999999999@s.whatsapp.net')

      expect(enrichment_service).not_to have_received(:perform)
    end

    it 'runs when profile_pic_url is present even if the contact was enriched recently' do
      contact.update!(
        additional_attributes: {
          Custom::Whatsapp::Evolution::ContactEnrichmentService::EVOLUTION_ENRICHED_AT_KEY => Time.current.utc.iso8601(3)
        }
      )
      allow(Custom::Whatsapp::Evolution::ContactEnrichmentService).to receive(:enrichment_stale?).and_return(false)

      described_class.perform_now(
        channel.id,
        contact.id,
        profile_pic_url: 'https://pps.whatsapp.net/v/example.jpg'
      )

      expect(enrichment_service).to have_received(:perform)
    end
  end
end
