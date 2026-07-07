# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter do
  describe '.canonicalize_data' do
    it 'maps Info/Message PascalCase payloads' do
      data = {
        'Info' => {
          'ID' => 'MSG123',
          'Chat' => '5511999999999@s.whatsapp.net',
          'SenderAlt' => '5511999999999@s.whatsapp.net',
          'IsFromMe' => false,
          'PushName' => 'Maria',
          'Timestamp' => 1_699_999_999
        },
        'Message' => {
          'conversation' => 'Hello'
        }
      }

      result = described_class.canonicalize_data(data)

      expect(result[:key][:id]).to eq('MSG123')
      expect(result[:key][:remoteJidAlt]).to eq('5511999999999@s.whatsapp.net')
      expect(result[:message][:conversation]).to eq('Hello')
      expect(result[:pushName]).to eq('Maria')
    end

    it 'unwraps ephemeral nested messages' do
      data = {
        'Info' => {
          'ID' => 'EPH1',
          'Chat' => '5511999999999@s.whatsapp.net',
          'IsFromMe' => false
        },
        'Message' => {
          'ephemeralMessage' => {
            'message' => {
              'conversation' => 'Hidden text'
            }
          }
        }
      }

      result = described_class.canonicalize_data(data)

      expect(result[:message][:conversation]).to eq('Hidden text')
    end

    it 'returns empty hash for nil data' do
      expect(described_class.canonicalize_data(nil)).to eq({})
    end
  end
end
