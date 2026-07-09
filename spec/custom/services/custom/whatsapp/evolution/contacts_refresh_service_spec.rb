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

    result = described_class.new(channel: channel).perform

    expect(result[:enqueued]).to eq(1)
  end

  it 'raises when a refresh is already running' do
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
