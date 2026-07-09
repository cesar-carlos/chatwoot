# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::ClaimGuard do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: create(:conversation, account: account, inbox: inbox),
      contact: create(:contact, account: account),
      provider: :wavoip,
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

  it 'is false when the call is unclaimed' do
    expect(described_class.claimed?(call)).to be(false)
  end

  it 'is true when accepted_by_agent_id is set' do
    call.update!(accepted_by_agent_id: agent.id)

    expect(described_class.claimed?(call)).to be(true)
  end

  it 'is false when only JoiningAgentCache has a claim' do
    Wavoip::Calls::JoiningAgentCache.write(call.id, agent.id)

    expect(described_class.claimed?(call)).to be(false)
  end

  it 'is false for a blank call' do
    expect(described_class.claimed?(nil)).to be(false)
  end
end
