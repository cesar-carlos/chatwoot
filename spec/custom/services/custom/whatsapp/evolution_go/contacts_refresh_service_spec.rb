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

    result = described_class.new(channel: channel).perform

    expect(result[:enqueued]).to eq(2)
    expect(result[:spacing_seconds]).to eq(3)
    expect(result[:eta_seconds]).to eq(6)
    expect(waits).to contain_exactly(0.seconds, 3.seconds)
    expect(Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob).to have_received(:set).twice
  end

  it 'raises when a refresh is already running' do
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
end
