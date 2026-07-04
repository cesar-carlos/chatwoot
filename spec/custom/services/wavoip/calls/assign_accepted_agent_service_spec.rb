# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::AssignAcceptedAgentService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :wavoip,
      direction: :incoming,
      status: 'in_progress'
    )
  end

  it 'assigns accepted_by_agent_id from the joining agent cache' do
    Wavoip::Calls::JoiningAgentCache.write(call.id, agent.id)

    described_class.new(call: call).perform!

    expect(call.reload.accepted_by_agent_id).to eq(agent.id)
    expect(Wavoip::Calls::JoiningAgentCache.read(call.id)).to be_nil
  end

  it 'does not overwrite an existing accepted_by_agent_id' do
    other = create(:user, account: account)
    call.update!(accepted_by_agent_id: other.id)
    Wavoip::Calls::JoiningAgentCache.write(call.id, agent.id)

    described_class.new(call: call).perform!

    expect(call.reload.accepted_by_agent_id).to eq(other.id)
  end

  it 'does nothing when the joining agent cache is empty' do
    described_class.new(call: call).perform!

    expect(call.reload.accepted_by_agent_id).to be_nil
  end
end
