# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::CallStatusApplier do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:status_mapper) { Wavoip::Calls::StatusMapper.new }
  let(:broadcaster) do
    instance_double(
      Wavoip::Calls::Broadcaster,
      broadcast_incoming: nil,
      broadcast_accepted: nil,
      broadcast_agent_accepted: nil,
      broadcast_ended: nil
    )
  end
  let(:provider_call_id) { 'wavoip_status_applier_001' }

  def build_event(overrides = {})
    defaults = {
      provider: :wavoip,
      external_call_id: provider_call_id,
      action: :update,
      external_status: 'ENDED',
      direction: :outgoing,
      from_phone: channel.phone_number,
      to_phone: '+15550009999',
      peer_name: 'Outbound Contact',
      duration_seconds: nil,
      session_id: 12_345,
      call_type: :official,
      record_url: nil,
      raw_type: 'CALL'
    }
    Voice::Dto::WebhookCallEvent.new(**defaults, **overrides)
  end

  def applier_for(event)
    described_class.new(
      inbox: inbox,
      event: event,
      status_mapper: status_mapper,
      broadcaster: broadcaster
    )
  end

  def create_call(**attrs)
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :wavoip,
      provider_call_id: provider_call_id,
      direction: :outgoing,
      status: 'ringing',
      **attrs
    )
  end

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
  end

  it 'persists no_answer but defers broadcast_ended for outbound still ringing' do
    call = create_call

    result = applier_for(build_event(external_status: 'ENDED')).apply!(call, broadcast: true)

    aggregate_failures do
      expect(result).to be(true)
      expect(call.reload.status).to eq('no_answer')
      expect(call.started_at).to be_nil
      expect(broadcaster).not_to have_received(:broadcast_ended)
    end
  end

  it 'broadcasts ended for outbound that reached in_progress' do
    call = create_call(status: 'in_progress', started_at: 1.minute.ago)

    applier_for(build_event(external_status: 'ENDED', duration_seconds: 30)).apply!(call, broadcast: true)

    aggregate_failures do
      expect(call.reload.status).to eq('completed')
      expect(broadcaster).to have_received(:broadcast_ended).with(call)
    end
  end

  it 'broadcasts ended for inbound ringing to no_answer' do
    call = create_call(direction: :incoming, from_phone: '+15550001111', to_phone: channel.phone_number)

    applier_for(
      build_event(
        direction: :incoming,
        external_status: 'NOT_ANSWERED',
        from_phone: '+15550001111',
        to_phone: channel.phone_number
      )
    ).apply!(call, broadcast: true)

    aggregate_failures do
      expect(call.reload.status).to eq('no_answer')
      expect(broadcaster).to have_received(:broadcast_ended).with(call)
    end
  end
end
