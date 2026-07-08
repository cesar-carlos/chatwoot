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

    it 'maps fromMe payloads to the recipient peer JID' do
      data = {
        'Info' => {
          'ID' => 'MSG-FROM-ME',
          'Chat' => '556696971841@s.whatsapp.net',
          'Sender' => '5511999999999:38@s.whatsapp.net',
          'SenderAlt' => '5511999999999@s.whatsapp.net',
          'RecipientAlt' => '556696971841@s.whatsapp.net',
          'IsFromMe' => true,
          'PushName' => 'Agent',
          'Timestamp' => 1_699_999_999
        },
        'Message' => {
          'conversation' => 'From phone'
        }
      }

      result = described_class.canonicalize_data(data)

      expect(result[:key][:remoteJid]).to eq('556696971841@s.whatsapp.net')
      expect(result[:key][:remoteJidAlt]).to eq('556696971841@s.whatsapp.net')
      expect(result[:key][:fromMe]).to be(true)
    end

    it 'uses RecipientAlt for fromMe LID chats' do
      data = {
        'Info' => {
          'ID' => 'MSG-FROM-ME-LID',
          'Chat' => '123456789012345@lid',
          'Sender' => '5511999999999:38@s.whatsapp.net',
          'SenderAlt' => '5511999999999@s.whatsapp.net',
          'RecipientAlt' => '556696971841@s.whatsapp.net',
          'IsFromMe' => true
        },
        'Message' => {
          'conversation' => 'From phone'
        }
      }

      result = described_class.canonicalize_data(data)

      expect(result[:key][:remoteJid]).to eq('123456789012345@lid')
      expect(result[:key][:remoteJidAlt]).to eq('556696971841@s.whatsapp.net')
    end

    it 'returns empty hash for nil data' do
      expect(described_class.canonicalize_data(nil)).to eq({})
    end
  end
end
