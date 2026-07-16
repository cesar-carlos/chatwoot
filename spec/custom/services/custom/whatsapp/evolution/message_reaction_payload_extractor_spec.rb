# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::MessageReactionPayloadExtractor do
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
      expect(payload[:from_me]).to be(false)
    end

    it 'marks blank text as removal' do
      data = {
        'key' => { 'id' => 'REACTION1', 'fromMe' => true },
        'message' => {
          'reactionMessage' => {
            'text' => '',
            'key' => { 'id' => 'TARGETMSG1', 'remoteJid' => '5511@s.whatsapp.net' }
          }
        }
      }

      payload = described_class.extract_reaction_payload(data)
      expect(payload[:remove]).to be(true)
    end
  end
end
