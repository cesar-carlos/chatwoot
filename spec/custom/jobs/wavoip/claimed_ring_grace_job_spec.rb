# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::ClaimedRingGraceJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: create(:conversation, account: account, inbox: inbox),
      contact: create(:contact, account: account),
      provider: :wavoip,
      provider_call_id: 'claimed_grace_001',
      direction: :incoming,
      status: 'ringing',
      accepted_by_agent_id: agent.id
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
    Voice::CallMessageBuilder.new(call).perform!
  end

  it 'schedules at most once via Redis lock' do
    expect do
      2.times { described_class.schedule_if_needed(call) }
    end.to have_enqueued_job(described_class).with(call.id).exactly(:once)
  end

  it 'force-closes a still-ringing claimed call as claimed_stale' do
    described_class.perform_now(call.id)

    expect(call.reload.status).to eq('no_answer')
    expect(call.end_reason).to eq('claimed_stale')
  end

  it 'no-ops when the call already left ringing' do
    call.update!(status: 'in_progress', started_at: Time.current)

    described_class.perform_now(call.id)

    expect(call.reload.status).to eq('in_progress')
  end
end
