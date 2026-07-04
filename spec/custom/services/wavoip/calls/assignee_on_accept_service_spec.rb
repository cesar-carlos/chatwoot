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

  it 'assigns the accepting agent to the conversation' do
    described_class.new(call: call, agent: agent).perform!

    expect(conversation.reload.assignee).to eq(agent)
  end

  it 'does not overwrite an existing assignee' do
    other = create(:user, account: account)
    conversation.update!(assignee: other)

    described_class.new(call: call, agent: agent).perform!

    expect(conversation.reload.assignee).to eq(other)
  end
end
