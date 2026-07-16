# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::MessageReactionPayloadExtractor do
  describe '.extract_reaction_payload' do
    it 'extracts reaction emoji and target key' do
      data = {
        'key' => {
          'remoteJid' => '5511999999999@s.whatsapp.net',
          'fromMe' => false,
          'id' => 'REACTION1'
        },
        'message' => {
          'reactionMessage' => {
            'text' => '👍',
            'key' => {
              'id' => 'TARGETMSG1',
              'remoteJid' => '5511999999999@s.whatsapp.net',
              'fromMe' => true
            }
          }
        }
      }

      payload = described_class.extract_reaction_payload(data)

      expect(payload[:key][:id]).to eq('TARGETMSG1')
      expect(payload[:text]).to eq('👍')
      expect(payload[:remove]).to be(false)
      expect(payload[:reaction_message_id]).to eq('REACTION1')
      expect(payload[:from_me]).to be(false)
    end

    it 'marks empty text and remove as removal' do
      data = {
        'key' => { 'id' => 'REACTION2', 'fromMe' => false, 'remoteJid' => '5511999999999@s.whatsapp.net' },
        'message' => {
          'reactionMessage' => {
            'text' => '',
            'key' => { 'id' => 'TARGETMSG1', 'remoteJid' => '5511999999999@s.whatsapp.net', 'fromMe' => true }
          }
        }
      }

      payload = described_class.extract_reaction_payload(data)

      expect(payload[:remove]).to be(true)
    end

    it 'accepts PascalCase reaction fields' do
      data = {
        'key' => { 'ID' => 'REACTION3', 'FromMe' => false, 'RemoteJid' => '5511999999999@s.whatsapp.net' },
        'message' => {
          'reactionMessage' => {
            'Text' => '❤️',
            'key' => { 'ID' => 'TARGETMSG2', 'RemoteJID' => '5511999999999@s.whatsapp.net', 'FromMe' => true }
          }
        }
      }

      payload = described_class.extract_reaction_payload(data)

      expect(payload[:key][:id]).to eq('TARGETMSG2')
      expect(payload[:text]).to eq('❤️')
    end

    it 'returns nil for non-reaction messages' do
      payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_inbound.json').read)

      expect(described_class.extract_reaction_payload(payload['data'])).to be_nil
    end
  end
end
