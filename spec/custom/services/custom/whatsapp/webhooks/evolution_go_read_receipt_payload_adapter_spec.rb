# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Webhooks::EvolutionGoReadReceiptPayloadAdapter do
  describe '.canonicalize_data' do
    it 'maps official Receipt payload fields' do
      data = {
        'Chat' => '5511999999999@s.whatsapp.net',
        'Sender' => '5511888888888:5@s.whatsapp.net',
        'MessageIDs' => %w[MSG1 MSG2],
        'Timestamp' => '2024-10-10T17:18:00-03:00',
        'Type' => 'read'
      }

      result = described_class.canonicalize_data(data, envelope_state: 'Read')

      expect(result[:key][:id]).to eq('MSG1')
      expect(result[:message_ids]).to eq(%w[MSG1 MSG2])
      expect(result[:key][:remoteJid]).to eq('5511999999999@s.whatsapp.net')
      expect(result[:receipt_state]).to eq('Read')
      expect(result[:timestamp]).to eq(Time.zone.parse('2024-10-10T17:18:00-03:00').to_i.to_s)
    end

    it 'returns legacy key payloads unchanged' do
      data = { key: { id: 'LEGACY1', remoteJid: '5511@s.whatsapp.net' } }

      expect(described_class.canonicalize_data(data)[:key][:id]).to eq('LEGACY1')
    end

    it 'returns empty hash for blank data' do
      expect(described_class.canonicalize_data(nil)).to eq({})
    end
  end
end
