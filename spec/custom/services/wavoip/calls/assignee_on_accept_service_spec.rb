# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::AssigneeOnAcceptService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, assignee: nil)
  end
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :wavoip,
      direction: :incoming,
      status: 'ringing'
    )
  end

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
    create(:inbox_member, inbox: inbox, user: agent)
  end

  it 'assigns the accepting agent when auto-assignment is enabled and assignee is blank' do
    inbox.update!(enable_auto_assignment: true)

    described_class.new(call: call, agent: agent).perform!

    expect(conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'does not steal an existing assignee' do
    inbox.update!(enable_auto_assignment: true)
    conversation.update!(assignee: other_agent)

    described_class.new(call: call, agent: agent).perform!

    expect(conversation.reload.assignee_id).to eq(other_agent.id)
  end

  it 'does not assign when auto-assignment is disabled' do
    inbox.update!(enable_auto_assignment: false)

    described_class.new(call: call, agent: agent).perform!

    expect(conversation.reload.assignee_id).to be_nil
  end
end
