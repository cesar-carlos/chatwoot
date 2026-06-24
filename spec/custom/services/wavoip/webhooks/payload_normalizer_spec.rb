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
        expect(event.raw_type).to eq('RECORD')
      end
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
  end
end
