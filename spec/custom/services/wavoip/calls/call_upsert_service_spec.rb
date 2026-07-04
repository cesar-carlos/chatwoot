# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::CallUpsertService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:broadcaster) do
    instance_double(
      Wavoip::Calls::Broadcaster,
      broadcast_incoming: nil,
      broadcast_accepted: nil,
      broadcast_agent_accepted: nil,
      broadcast_ended: nil
    )
  end
  let(:provider_call_id) { 'wavoip_call_upsert_001' }

  def build_event(overrides = {})
    defaults = {
      provider: :wavoip,
      external_call_id: provider_call_id,
      action: :create,
      external_status: 'INCOMING_RING',
      direction: :incoming,
      from_phone: '+15550001111',
      to_phone: channel.phone_number,
      peer_name: 'Caller Test',
      duration_seconds: nil,
      session_id: 12_345,
      call_type: :official,
      record_url: nil,
      record_status: nil,
      raw_type: 'CALL'
    }
    Voice::Dto::WebhookCallEvent.new(**defaults, **overrides)
  end

  def service_for(event)
    described_class.new(inbox: inbox, event: event, broadcaster: broadcaster)
  end

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
  end

  describe '#create!' do
    it 'creates a single Call and voice_call message' do
      event = build_event

      call = nil
      expect { call = service_for(event).create! }
        .to change(Call, :count).by(1)
        .and change(Message, :count).by(1)

      aggregate_failures do
        expect(call.provider).to eq('wavoip')
        expect(call.provider_call_id).to eq(provider_call_id)
        expect(call.status).to eq('ringing')
        expect(call.message).to be_present
        expect(call.message.content_type).to eq('voice_call')
        expect(call.message_id).to eq(call.message.id)
      end
    end

    it 'is idempotent when the call already exists' do
      event = build_event
      first = service_for(event).create!
      second = nil

      expect { second = service_for(event).create! }.not_to change(Call, :count)
      expect(second.id).to eq(first.id)
    end

    it 'reopens a resolved conversation when create is retried for an existing call' do
      contact = create(:contact, account: account, phone_number: '+15550001111')
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        status: :resolved
      )
      create(
        :call,
        account: account,
        inbox: inbox,
        conversation: conversation,
        contact: contact,
        provider: :wavoip,
        provider_call_id: provider_call_id,
        direction: :incoming,
        status: 'ringing'
      )

      service_for(build_event).create!

      expect(conversation.reload).to be_pending
    end

    it 're-applies status when create arrives after the call record exists' do
      create(
        :call,
        account: account,
        inbox: inbox,
        conversation: create(:conversation, account: account, inbox: inbox),
        contact: create(:contact, account: account),
        provider: :wavoip,
        provider_call_id: provider_call_id,
        direction: :incoming,
        status: 'ringing'
      )
      duplicate_create = build_event(external_status: 'ACTIVE')

      result = service_for(duplicate_create).create!

      expect(result.reload.status).to eq('in_progress')
    end

    it 'skips inbound create when inbound_calls_enabled is false' do
      channel.update!(provider_config: channel.provider_config.merge('inbound_calls_enabled' => false))

      expect { service_for(build_event).create! }.not_to change(Call, :count)
    end

    it 'marks the channel webhook as verified on first create' do
      service_for(build_event).create!

      expect(channel.reload.webhook_verified?).to be(true)
    end

    it 'creates a call from the live caller/receiver outbound fixture without skipping' do
      channel.update!(phone_number: '+5566999050312')
      payload = JSON.parse(file_fixture('wavoip/call_create_outcoming_live_caller_receiver.json').read)
      event = Wavoip::Webhooks::PayloadNormalizer.new(payload).normalize

      call = nil
      expect { call = service_for(event).create! }
        .to change(Call, :count).by(1)

      expect(call.status).to eq('ringing')
      expect(broadcaster).not_to have_received(:broadcast_incoming)
    end

    it 'creates a call from the live caller/receiver inbound fixture without skipping' do
      channel.update!(phone_number: '+5566997193168')
      payload = JSON.parse(file_fixture('wavoip/call_create_incoming_live_caller_receiver.json').read)
      event = Wavoip::Webhooks::PayloadNormalizer.new(payload).normalize

      call = service_for(event).create!

      aggregate_failures do
        expect(call).to be_present
        expect(call.incoming?).to be(true)
        expect(call.status).to eq('ringing')
      end
    end
  end

  describe '#update!' do
    it 'creates the call when update arrives before create' do
      event = build_event(action: :update, external_status: 'INCOMING_RING')

      expect { service_for(event).update! }.to change(Call, :count).by(1)
    end

    it 'transitions ringing to in_progress on ACTIVE' do
      service_for(build_event).create!
      active_event = build_event(action: :update, external_status: 'ACTIVE')

      call = service_for(active_event).update!

      aggregate_failures do
        expect(call.status).to eq('in_progress')
        expect(call.started_at).to be_present
        expect(broadcaster).to have_received(:broadcast_agent_accepted).with(
          call,
          accepted_by_agent_id: call.accepted_by_agent_id
        )
      end
    end

    it 'no-ops terminal to ringing transitions' do
      create_event = build_event
      service_for(create_event).create!
      service_for(build_event(action: :update, external_status: 'ACTIVE')).update!
      ended_event = build_event(action: :update, external_status: 'ENDED', duration_seconds: 42)
      service_for(ended_event).update!

      ring_again = build_event(action: :update, external_status: 'INCOMING_RING')
      result = service_for(ring_again).update!

      expect(result.status).to eq('completed')
      expect(broadcaster).not_to have_received(:broadcast_incoming)
    end

    it 'no-ops transitions between different terminal statuses' do
      service_for(build_event).create!
      service_for(build_event(action: :update, external_status: 'ACTIVE')).update!
      service_for(build_event(action: :update, external_status: 'ENDED', duration_seconds: 30)).update!

      late_no_answer = build_event(action: :update, external_status: 'NOT_ANSWERED')
      result = service_for(late_no_answer).update!

      expect(result.status).to eq('completed')
      expect(broadcaster).to have_received(:broadcast_ended).once
    end

    it 'records handled_remotely end reason and completes the call' do
      service_for(build_event).create!
      remote_event = build_event(action: :update, external_status: 'HANDLED_REMOTELY')

      call = service_for(remote_event).update!

      aggregate_failures do
        expect(call.status).to eq('completed')
        expect(call.end_reason).to eq('handled_remotely')
        expect(broadcaster).to have_received(:broadcast_ended).with(call)
      end
    end

    it 'creates handled_remotely stub when create returns blank on first HANDLED_REMOTELY' do
      remote_event = build_event(action: :update, external_status: 'HANDLED_REMOTELY')
      service = service_for(remote_event)
      allow(service).to receive(:create!).and_return(nil)

      call = service.update!

      aggregate_failures do
        expect(call.status).to eq('completed')
        expect(call.end_reason).to eq('handled_remotely')
        expect(broadcaster).to have_received(:broadcast_ended).with(call)
      end
    end

    it 'ignores REMOTE_CALL_IN_PROGRESS without changing status' do
      call = service_for(build_event).create!
      ignore_event = build_event(action: :update, external_status: 'REMOTE_CALL_IN_PROGRESS')

      result = service_for(ignore_event).update!

      expect(result.status).to eq(call.status)
    end

    it 'skips create on update when contact phone is missing (no peer on UPDATE)' do
      channel.update!(phone_number: '+5511999999999')
      event = build_event(
        action: :update,
        external_status: 'INCOMING_RING',
        from_phone: nil,
        to_phone: channel.phone_number
      )

      expect { service_for(event).update! }.not_to change(Call, :count)
    end

    it 'defers broadcast_ended when outbound ENDED arrives while still ringing' do
      channel.update!(phone_number: '+5566999050312')
      payload = JSON.parse(file_fixture('wavoip/call_create_outcoming_live_caller_receiver.json').read)
      create_event = Wavoip::Webhooks::PayloadNormalizer.new(payload).normalize
      call = service_for(create_event).create!

      ended_event = Wavoip::Webhooks::PayloadNormalizer.new(
        payload.merge('action' => 'UPDATE', 'status' => 'ENDED', 'duration' => 0)
      ).normalize
      service_for(ended_event).update!

      aggregate_failures do
        expect(call.reload.status).to eq('no_answer')
        expect(call.started_at).to be_nil
        expect(broadcaster).not_to have_received(:broadcast_ended)
      end
    end

    it 'persists record_status from CALL updates even when status is unchanged' do
      call = service_for(build_event).create!
      call.update!(status: 'in_progress', meta: { 'wavoip_status' => 'ACTIVE' })

      ignore_event = build_event(
        action: :update,
        external_status: 'ACTIVE',
        record_status: 'RECORDING'
      )

      service_for(ignore_event).update!

      expect(call.reload.meta['record_status']).to eq('RECORDING')
    end
  end
end
