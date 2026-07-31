# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::ProtocolNoise do
  describe '.protocol_only?' do
    it 'detects protocolMessage-only envelopes' do
      data = {
        'message' => {
          'protocolMessage' => { 'type' => 'EPHEMERAL_SETTING' }
        }
      }

      expect(described_class.protocol_only?(data)).to be(true)
    end

    it 'detects secretEncryptedMessage-only envelopes' do
      data = {
        'message' => {
          'messageContextInfo' => {},
          'secretEncryptedMessage' => { 'targetMessageKey' => { 'id' => 'X' } }
        }
      }

      expect(described_class.protocol_only?(data)).to be(true)
    end

    it 'returns false for regular conversation text' do
      data = { 'message' => { 'conversation' => 'hello' } }

      expect(described_class.protocol_only?(data)).to be(false)
    end
  end
end
