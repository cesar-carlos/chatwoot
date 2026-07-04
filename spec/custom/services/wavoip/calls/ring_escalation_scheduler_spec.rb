# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::RingEscalationScheduler do
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
      provider_call_id: 'scheduler_test_001',
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

  it 'enqueues EscalateRingJob only once when schedule is called multiple times' do
    scheduler = described_class.new(call: call)

    expect do
      3.times { scheduler.schedule }
    end.to have_enqueued_job(Wavoip::EscalateRingJob).with(call.id).exactly(:once)
  end

  it 'does not enqueue when ring_timeout_seconds is zero' do
    channel.update!(provider_config: channel.provider_config.merge('ring_timeout_seconds' => 0))
    scheduler = described_class.new(call: call)

    expect do
      scheduler.schedule
    end.not_to have_enqueued_job(Wavoip::EscalateRingJob)
  end

  it 'acquires the lock atomically via unless_exist (no read-then-write race)' do
    scheduler = described_class.new(call: call)

    expect(Rails.cache).to receive(:write).with(
      "wavoip:escalate_lock:#{call.id}", true, hash_including(unless_exist: true)
    ).and_call_original

    scheduler.schedule
  end
end
