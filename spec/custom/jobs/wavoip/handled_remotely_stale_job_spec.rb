# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::HandledRemotelyStaleJob do
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
      provider_call_id: 'handled_remotely_stale_001',
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

  it 'completes a claimed ringing call as handled_remotely' do
    described_class.perform_now(call.id)

    expect(call.reload.status).to eq('completed')
    expect(call.end_reason).to eq('handled_remotely')
  end

  it 'no-ops when already in_progress' do
    call.update!(status: 'in_progress', started_at: Time.current)

    described_class.perform_now(call.id)

    expect(call.reload.status).to eq('in_progress')
  end
end
