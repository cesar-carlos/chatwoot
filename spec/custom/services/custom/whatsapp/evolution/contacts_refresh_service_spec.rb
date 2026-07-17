# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::ContactsRefreshService do
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
        'api_key' => 'TEST-INSTANCE-API-KEY'
      )
    )
  end
  let(:inbox) { channel.inbox }

  before do
    Redis::Alfred.delete(
      format(Redis::RedisKeys::EVOLUTION_CONTACTS_REFRESH_LOCK, channel_id: channel.id)
    )
  end

  it 'enqueues forced enrichment for every inbox contact' do
    contact = create(:contact, account: account, phone_number: '+5511999999999')
    create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511999999999')

    expect(Custom::Whatsapp::Evolution::ContactEnrichmentJob).to receive(:perform_later).with(
      channel.id,
      contact.id,
      hash_including(force: true)
    )

    release_job = class_double(Custom::Whatsapp::Evolution::ContactsRefreshLockReleaseJob)
    allow(Custom::Whatsapp::Evolution::ContactsRefreshLockReleaseJob).to receive(:set)
      .and_return(release_job)
    allow(release_job).to receive(:perform_later)

    result = described_class.new(channel: channel).perform

    expect(result[:enqueued]).to eq(1)
    expect(result[:running]).to be(true)
    expect(result[:remaining_seconds]).to eq(described_class::LOCK_TTL)
    expect(Custom::Whatsapp::Evolution::ContactsRefreshLockReleaseJob).to have_received(:set)
      .with(wait: described_class::LOCK_TTL.seconds)
  end

  it 'returns empty result without locking when inbox has no contacts' do
    result = described_class.new(channel: channel).perform

    expect(result).to eq(enqueued: 0, running: false, remaining_seconds: 0)
    expect(described_class.lock_status(channel)[:running]).to be(false)
  end

  it 'raises when a refresh is already running' do
    contact = create(:contact, account: account, phone_number: '+5511999999999')
    create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511999999999')

    Redis::Alfred.set(
      format(Redis::RedisKeys::EVOLUTION_CONTACTS_REFRESH_LOCK, channel_id: channel.id),
      true,
      nx: true,
      ex: 60
    )

    expect do
      described_class.new(channel: channel).perform
    end.to raise_error(described_class::AlreadyRunningError)
  end
end
