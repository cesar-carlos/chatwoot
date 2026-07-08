# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::StaleCallTimeoutScheduler do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_wavoip, account: account, provider_config: { 'ring_timeout_seconds' => 30 })
  end
  let(:inbox) { channel.inbox }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: create(:conversation, account: account, inbox: inbox),
      contact: create(:contact, account: account),
      provider: :wavoip,
      provider_call_id: 'stale_timeout_001',
      direction: :incoming,
      status: 'ringing'
    )
  end

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
    Rails.cache.clear
  end

  it 'enqueues AutoNoAnswerRingJob at twice the configured ring timeout' do
    scheduler = described_class.new(call: call)

    expect { scheduler.schedule }
      .to have_enqueued_job(Wavoip::AutoNoAnswerRingJob).with(call.id)
  end

  it 'enqueues only once across repeated calls' do
    scheduler = described_class.new(call: call)

    expect do
      3.times { scheduler.schedule }
    end.to have_enqueued_job(Wavoip::AutoNoAnswerRingJob).exactly(:once)
  end

  it 'falls back to the default timeout when ring_timeout_seconds is unset' do
    channel.update!(provider_config: channel.provider_config.merge('ring_timeout_seconds' => 0))
    scheduler = described_class.new(call: call)

    expect { scheduler.schedule }
      .to have_enqueued_job(Wavoip::AutoNoAnswerRingJob).with(call.id)
  end

  it 'schedules outbound calls with the longer, separate outbound timeout' do
    call.update!(direction: :outgoing)
    scheduler = described_class.new(call: call)

    expect { scheduler.schedule }
      .to have_enqueued_job(Wavoip::AutoNoAnswerRingJob).with(call.id)
  end

  it 'respects a configured outbound_stale_timeout_seconds override' do
    channel.update!(provider_config: channel.provider_config.merge('outbound_stale_timeout_seconds' => 60))
    call.update!(direction: :outgoing)
    scheduler = described_class.new(call: call)

    expect { scheduler.schedule }
      .to have_enqueued_job(Wavoip::AutoNoAnswerRingJob).with(call.id)
  end

  it 'acquires the lock atomically via unless_exist (no read-then-write race)' do
    scheduler = described_class.new(call: call)

    expect(Rails.cache).to receive(:write).with(
      "wavoip:stale_ring_lock:#{call.id}", true, hash_including(unless_exist: true)
    ).and_call_original

    scheduler.schedule
  end
end
