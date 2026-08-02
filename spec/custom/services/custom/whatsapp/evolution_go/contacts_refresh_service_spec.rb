# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::ContactsRefreshService do
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
        'instance_token' => 'token'
      )
    )
  end
  let(:inbox) { channel.inbox }

  before do
    Redis::Alfred.delete(
      format(Redis::RedisKeys::EVOLUTION_GO_CONTACTS_REFRESH_LOCK, channel_id: channel.id)
    )
  end

  # rubocop:disable RSpec/MultipleExpectations -- paced enqueue + lock release contract
  it 'enqueues paced forced enrichment for every inbox contact' do
    contact_a = create(:contact, account: account, phone_number: '+5511888888888')
    contact_b = create(:contact, account: account, phone_number: '+5511777777777')
    create(:contact_inbox, inbox: inbox, contact: contact_a, source_id: '5511888888888')
    create(:contact_inbox, inbox: inbox, contact: contact_b, source_id: '5511777777777')

    waits = []
    allow(Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob).to receive(:set) do |opts|
      waits << opts[:wait]
      job = class_double(Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob)
      allow(job).to receive(:perform_later)
      job
    end

    release_job = class_double(Custom::Whatsapp::EvolutionGo::ContactsRefreshLockReleaseJob)
    allow(Custom::Whatsapp::EvolutionGo::ContactsRefreshLockReleaseJob).to receive(:set)
      .and_return(release_job)
    allow(release_job).to receive(:perform_later)

    result = described_class.new(channel: channel).perform

    expect(result[:enqueued]).to eq(2)
    expect(result[:spacing_seconds]).to eq(3)
    expect(result[:eta_seconds]).to eq(6)
    expect(result[:running]).to be(true)
    expect(result[:remaining_seconds]).to eq(6 + described_class::LOCK_TTL_BUFFER)
    expect(waits).to contain_exactly(0.seconds, 3.seconds)
    expect(Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob).to have_received(:set).twice
    expect(Custom::Whatsapp::EvolutionGo::ContactsRefreshLockReleaseJob).to have_received(:set)
      .with(wait: (6 + described_class::LOCK_TTL_BUFFER).seconds)
    expect(release_job).to have_received(:perform_later).with(channel.id)
  end
  # rubocop:enable RSpec/MultipleExpectations

  it 'returns empty result without locking when inbox has no contacts' do
    result = described_class.new(channel: channel).perform

    expect(result).to eq(
      enqueued: 0,
      spacing_seconds: 3,
      eta_seconds: 0,
      running: false,
      remaining_seconds: 0
    )
    expect(described_class.lock_status(channel)[:running]).to be(false)
  end

  it 'raises when a refresh is already running' do
    contact = create(:contact, account: account, phone_number: '+5511888888888')
    create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511888888888')

    Redis::Alfred.set(
      format(Redis::RedisKeys::EVOLUTION_GO_CONTACTS_REFRESH_LOCK, channel_id: channel.id),
      true,
      nx: true,
      ex: 60
    )

    expect do
      described_class.new(channel: channel).perform
    end.to raise_error(described_class::AlreadyRunningError)
  end

  it 'exposes lock status with remaining ttl' do
    Redis::Alfred.set(
      format(Redis::RedisKeys::EVOLUTION_GO_CONTACTS_REFRESH_LOCK, channel_id: channel.id),
      true,
      nx: true,
      ex: 90
    )

    status = described_class.lock_status(channel)

    expect(status[:running]).to be(true)
    expect(status[:remaining_seconds]).to be_between(1, 90)
  end
end
