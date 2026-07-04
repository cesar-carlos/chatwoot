# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Webhooks::PayloadNormalizer do
  def load_fixture(name)
    JSON.parse(file_fixture("wavoip/#{name}.json").read)
  end

  def normalize(payload)
    described_class.new(payload).normalize
  end

  describe '#normalize' do
    it 'normalizes inbound CALL CREATE from fixture' do
      event = normalize(load_fixture('call_create_inbound_ring'))

      aggregate_failures do
        expect(event).to be_a(Voice::Dto::WebhookCallEvent)
        expect(event.provider).to eq(:wavoip)
        expect(event.external_call_id).to eq('wavoip_inbound_001')
        expect(event.action).to eq(:create)
        expect(event.external_status).to eq('INCOMING_RING')
        expect(event.direction).to eq(:incoming)
        expect(event.from_phone).to eq('+5511888888888')
        expect(event.to_phone).to eq('+5511999999999')
        expect(event.peer_name).to eq('Contato Teste')
        expect(event.call_type).to eq(:official)
        expect(event.raw_type).to eq('CALL')
      end
    end

    it 'maps OUTGOING direction from fixture' do
      event = normalize(load_fixture('call_create_outbound'))

      expect(event.direction).to eq(:outgoing)
    end

    it 'maps OUTCOMING direction defensively to outgoing' do
      event = normalize(load_fixture('call_create_outcoming'))

      expect(event.direction).to eq(:outgoing)
    end

    it 'infers outgoing direction from OUTGOING_RING when direction is missing' do
      event = normalize(
        {
          'type' => 'CALL',
          'action' => 'create',
          'whatsapp_call_id' => 'out_no_dir',
          'status' => 'OUTGOING_RING',
          'phone' => '+5511999999999',
          'peer' => { 'phone' => '+5511888888888' }
        }
      )

      expect(event.direction).to eq(:outgoing)
    end

    it 'infers outgoing when inbox phone is caller even if direction says INCOMING' do
      event = normalize(
        {
          'type' => 'CALL',
          'action' => 'create',
          'whatsapp_call_id' => 'agent_initiated',
          'status' => 'CALLING',
          'direction' => 'INCOMING',
          'phone' => '5566999050312',
          'caller' => '5566999050312',
          'receiver' => '556697193168'
        }
      )

      expect(event.direction).to eq(:outgoing)
    end

    it 'falls back to id when whatsapp_call_id is absent' do
      event = normalize(
        {
          'type' => 'CALL',
          'action' => 'create',
          'id' => 'legacy_call_id_001',
          'status' => 'INCOMING_RING',
          'direction' => 'INCOMING',
          'phone' => '+5511999999999',
          'peer' => { 'phone' => '+5511888888888' }
        }
      )

      expect(event.external_call_id).to eq('legacy_call_id_001')
    end

    it 'uses the last duplicate type field after JSON.parse (official CALL quirk)' do
      raw = '{"type":"RECORD","whatsapp_call_id":"dup_001","action":"CREATE","status":"INCOMING_RING",' \
            '"direction":"INCOMING","phone":"+5511999999999","type":"CALL"}'
      payload = JSON.parse(raw)
      event = normalize(payload)

      expect(event.raw_type).to eq('CALL')
      expect(event.external_call_id).to eq('dup_001')
    end

    it 'normalizes RECORD updates' do
      payload = {
        'type' => 'RECORD',
        'whatsapp_call_id' => 'rec_001',
        'phone' => '5511999999999',
        'record_url' => 'https://storage.wavoip.com/rec_001',
        'id_session' => 99
      }
      event = normalize(payload)

      aggregate_failures do
        expect(event.action).to eq(:update)
        expect(event.external_status).to eq('RECORD')
        expect(event.from_phone).to eq('+5511999999999')
        expect(event.record_url).to eq('https://storage.wavoip.com/rec_001')
        expect(event.record_status).to be_nil
        expect(event.raw_type).to eq('RECORD')
      end
    end

    it 'normalizes RECORD updates with record_status' do
      payload = {
        'type' => 'RECORD',
        'whatsapp_call_id' => 'rec_002',
        'phone' => '5511999999999',
        'record_url' => 'https://storage.wavoip.com/rec_002',
        'record_status' => 'READY'
      }
      event = normalize(payload)

      expect(event.record_status).to eq('READY')
    end

    it 'maps record_status on CALL events when present' do
      payload = {
        'type' => 'CALL',
        'action' => 'UPDATE',
        'whatsapp_call_id' => 'call_rec_status_001',
        'status' => 'ENDED',
        'record_status' => 'READY'
      }
      event = normalize(payload)

      expect(event.record_status).to eq('READY')
    end

    it 'normalizes DEVICE updates' do
      payload = {
        'type' => 'DEVICE',
        'status' => 'open',
        'phone' => '+5511999999999',
        'id_session' => 42
      }
      event = normalize(payload)

      aggregate_failures do
        expect(event.external_status).to eq('open')
        expect(event.from_phone).to eq('+5511999999999')
        expect(event.raw_type).to eq('DEVICE')
      end
    end

    it 'returns nil for unknown event types' do
      expect(normalize({ 'type' => 'UNKNOWN' })).to be_nil
    end

    it 'does not use inbox phone as contact on CALL UPDATE without peer' do
      payload = {
        'type' => 'CALL',
        'action' => 'UPDATE',
        'id' => 'wavoip_update_no_peer',
        'status' => 'ACTIVE',
        'direction' => 'INCOMING',
        'phone' => '+5511999999999'
      }
      event = normalize(payload)

      expect(event.from_phone).to be_nil
    end

    it 'normalizes inbound CALL CREATE from live caller/receiver fixture' do
      event = normalize(load_fixture('call_create_incoming_live_caller_receiver'))

      aggregate_failures do
        expect(event.direction).to eq(:incoming)
        expect(event.external_status).to eq('INCOMING_RING')
        expect(event.from_phone).to eq('+5566999050312')
        expect(event.to_phone).to eq('+5566997193168')
        expect(event.peer_name).to be_nil
      end
    end

    it 'normalizes outbound CALL CREATE from live caller/receiver fixture' do
      event = normalize(load_fixture('call_create_outcoming_live_caller_receiver'))

      aggregate_failures do
        expect(event.direction).to eq(:outgoing)
        expect(event.external_status).to eq('CALLING')
        expect(event.from_phone).to eq('+556692341814')
        expect(event.to_phone).to eq('+5566999050312')
      end
    end

    it 'prefers peer.phone over caller/receiver when both are present' do
      payload = load_fixture('call_create_incoming_live_caller_receiver').merge(
        'peer' => { 'phone' => '+5511888888888', 'display_name' => 'Peer Name' }
      )
      event = normalize(payload)

      aggregate_failures do
        expect(event.from_phone).to eq('+5511888888888')
        expect(event.peer_name).to eq('Peer Name')
      end
    end

    it 'leaves direction nil and logs on CREATE when direction is missing' do
      payload = {
        'type' => 'CALL',
        'action' => 'CREATE',
        'whatsapp_call_id' => 'missing_direction_001',
        'status' => 'INCOMING_RING',
        'peer' => { 'phone' => '+5511888888888' }
      }

      expect(Rails.logger).to receive(:warn).with(
        '[WAVOIP] CALL CREATE missing direction call_id=missing_direction_001'
      )

      event = normalize(payload)

      aggregate_failures do
        expect(event.direction).to be_nil
        expect(event.from_phone).to eq('+5511888888888')
      end
    end
  end
end
