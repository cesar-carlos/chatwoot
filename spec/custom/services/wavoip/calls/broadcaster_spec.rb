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
    allow(OnlineStatusTracker).to receive(:get_users_with_status)
      .with(account.id, user_ids: kind_of(Array), status: 'online')
      .and_return({ online_agent.id.to_s => 'online' })
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
    expect(payloads.first.last[:data][:call_direction]).to eq('inbound')
  end

  it 'does not broadcast incoming for outbound calls' do
    outbound_call = create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: contact,
      provider: :wavoip,
      provider_call_id: 'broadcast_out_001',
      direction: :outgoing,
      status: 'ringing'
    )
    broadcaster = described_class.new(inbox: inbox)
    payloads = []
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| payloads << [stream, payload] }

    broadcaster.broadcast_incoming(outbound_call)

    expect(payloads).to be_empty
  end

  it 'includes online administrators in the initial ring when configured' do
    admin = create(:user, :administrator, account: account)
    channel.update!(
      provider_config: channel.provider_config.merge('incoming_call_include_administrators' => true)
    )
    allow(OnlineStatusTracker).to receive(:get_users_with_status)
      .with(account.id, user_ids: kind_of(Array), status: 'online')
      .and_return({ admin.id.to_s => 'online' })

    broadcaster = described_class.new(inbox: inbox)
    payloads = []
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| payloads << [stream, payload] }

    broadcaster.broadcast_incoming(call)

    expect(payloads.map(&:first)).to include(admin.pubsub_token)
  end

  it 'broadcasts voice_call.accepted to inbox recipients not the full account stream' do
    broadcaster = described_class.new(inbox: inbox)
    payloads = []
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| payloads << [stream, payload] }

    broadcaster.broadcast_agent_accepted(call, accepted_by_agent_id: online_agent.id)

    streams = payloads.map(&:first)
    expect(streams).to include(online_agent.pubsub_token)
    expect(streams).not_to include("account_#{account.id}")
    expect(payloads.first.last[:event]).to eq('voice_call.accepted')
    expect(payloads.first.last[:data][:accepted_by_agent_id]).to eq(online_agent.id)
    expect(payloads.first.last[:data][:call_id]).to eq('broadcast_test_001')
  end

  it 'clears voice_call_incoming notifications when an agent accepts' do
    clearer = instance_double(Wavoip::Calls::ClearIncomingNotificationsService, perform: true)
    allow(Wavoip::Calls::ClearIncomingNotificationsService).to receive(:new)
      .with(call: call)
      .and_return(clearer)
    allow(ActionCable.server).to receive(:broadcast)

    described_class.new(inbox: inbox).broadcast_agent_accepted(
      call,
      accepted_by_agent_id: online_agent.id
    )

    expect(clearer).to have_received(:perform)
  end

  it 'does not rebroadcast incoming after an agent accepted' do
    call.update!(accepted_by_agent_id: online_agent.id)
    broadcaster = described_class.new(inbox: inbox)
    payloads = []
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| payloads << [stream, payload] }

    broadcaster.broadcast_incoming(call)
    broadcaster.broadcast_escalated_ring(call)

    expect(payloads).to be_empty
  end

  it 'broadcasts escalated ring to broad fallback recipients' do
    admin = create(:user, :administrator, account: account)
    create(:inbox_member, inbox: inbox, user: offline_agent)
    broadcaster = described_class.new(inbox: inbox)
    payloads = []
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| payloads << [stream, payload] }

    broadcaster.broadcast_escalated_ring(call)

    streams = payloads.map(&:first)
    expect(streams).to include(online_agent.pubsub_token, offline_agent.pubsub_token, admin.pubsub_token)
    expect(payloads.first.last[:event]).to eq('voice_call.incoming')
    expect(payloads.first.last[:data][:escalated]).to be(true)
  end
end
