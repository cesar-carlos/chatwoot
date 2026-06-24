# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::Broadcaster do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:online_agent) { create(:user, account: account, role: :agent) }
  let(:offline_agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, assignee: offline_agent)
  end
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: contact,
      provider: :wavoip,
      provider_call_id: 'broadcast_test_001',
      direction: :incoming,
      status: 'ringing'
    )
  end

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
    create(:inbox_member, inbox: inbox, user: online_agent)
    online_agent.account_users.find_by(account: account).update!(availability: :online)
    offline_agent.account_users.find_by(account: account).update!(availability: :offline)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(
      { online_agent.id.to_s => 'online' }
    )
  end

  it 'broadcasts incoming to online inbox members before assignee fallback' do
    broadcaster = described_class.new(inbox: inbox)
    payloads = []
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| payloads << [stream, payload] }

    broadcaster.broadcast_incoming(call)

    streams = payloads.map(&:first)
    expect(streams).to include(online_agent.pubsub_token)
    expect(streams).not_to include(offline_agent.pubsub_token)
    expect(payloads.first.last[:event]).to eq('voice_call.incoming')
  end

  it 'broadcasts voice_call.accepted with accepted_by_agent_id' do
    broadcaster = described_class.new(inbox: inbox)
    payloads = []
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| payloads << [stream, payload] }

    broadcaster.broadcast_agent_accepted(call, accepted_by_agent_id: online_agent.id)

    expect(payloads.first.last[:event]).to eq('voice_call.accepted')
    expect(payloads.first.last[:data][:accepted_by_agent_id]).to eq(online_agent.id)
    expect(payloads.first.last[:data][:call_id]).to eq('broadcast_test_001')
  end
end
