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
    agent.notification_settings.find_by(account: account).update!(push_conversation_creation: true)
  end

  it 'creates conversation_creation notification for inbox members' do
    expect do
      described_class.new(call: call, inbox: inbox).perform
    end.to change { agent.notifications.conversation_creation.count }.by(1)
  end
end
