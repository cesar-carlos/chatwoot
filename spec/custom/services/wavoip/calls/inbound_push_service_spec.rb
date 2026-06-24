# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::InboundPushService do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
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
      status: 'ringing'
    )
  end

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    agent.notification_settings.find_by(account: account).update!(push_voice_call_incoming: true)
  end

  it 'creates voice_call_incoming notification for inbox members' do
    expect do
      described_class.new(call: call, inbox: inbox).perform
    end.to change { agent.notifications.voice_call_incoming.count }.by(1)
  end

  it 'falls back to assignee then members when no agents are online' do
    offline_agent = create(:user, account: account, role: :agent)
    create(:inbox_member, user: offline_agent, inbox: inbox)
    offline_agent.notification_settings.find_by(account: account).update!(push_voice_call_incoming: true)
    conversation.update!(assignee: offline_agent)

    allow(inbox).to receive(:available_agents).and_return(User.none)

    expect do
      described_class.new(call: call, inbox: inbox).perform
    end.to change { offline_agent.notifications.voice_call_incoming.count }.by(1)
  end
end
