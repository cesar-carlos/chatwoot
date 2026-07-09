# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::ClearIncomingNotificationsService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
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
    create(:inbox_member, user: other_agent, inbox: inbox)
    agent.notification_settings.find_by(account: account).update!(push_voice_call_incoming: true)
    other_agent.notification_settings.find_by(account: account).update!(push_voice_call_incoming: true)

    [agent, other_agent].each do |user|
      NotificationBuilder.new(
        notification_type: 'voice_call_incoming',
        user: user,
        account: account,
        primary_actor: conversation,
        secondary_actor: call.contact
      ).perform
    end
  end

  it 'destroys voice_call_incoming notifications for the conversation' do
    expect do
      described_class.new(call: call).perform
    end.to change { conversation.notifications.voice_call_incoming.count }.from(2).to(0)
  end

  it 'does not destroy unrelated notification types' do
    assignment = NotificationBuilder.new(
      notification_type: 'conversation_assignment',
      user: agent,
      account: account,
      primary_actor: conversation
    ).perform

    described_class.new(call: call).perform

    expect(Notification.exists?(assignment.id)).to be(true)
  end
end
