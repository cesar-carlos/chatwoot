# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor do
  describe '.extract_delete_key' do
    it 'extracts revoke key from MESSAGE protocol payload' do
      payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_revoke.json').read)

      key = described_class.extract_delete_key(payload['data'], event: 'MESSAGE')

      expect(key[:id]).to eq('3EB0DELETEDMSG123')
      expect(key[:remoteJid]).to eq('5511999999999@s.whatsapp.net')
      expect(key[:fromMe]).to be(false)
    end

    it 'extracts key from explicit delete event payload' do
      data = {
        key: {
          id: 'MSG-DELETE-1',
          remoteJid: '5511999999999@s.whatsapp.net',
          fromMe: false
        }
      }

      key = described_class.extract_delete_key(data, event: 'MESSAGES_DELETE')

      expect(key[:id]).to eq('MSG-DELETE-1')
    end

    it 'extracts revoke key when protocol key uses PascalCase ID and remoteJID' do
      payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_revoke_pascal_case.json').read)

      key = described_class.extract_delete_key(payload['data'], event: 'MESSAGE')

      expect(key[:id]).to eq('3EB02445B521333CBE35E4')
      expect(key[:remoteJid]).to eq('216075593625789@lid')
      expect(key[:fromMe]).to be(true)
    end

    it 'extracts revoke when IsRevoke/messageType are set and only typeName matches' do
      data = {
        IsRevoke: true,
        messageType: 'revoke',
        Message: {
          protocolMessage: {
            type: 99,
            typeName: 'REVOKE',
            key: { ID: 'REV-TYPENAME', fromMe: false, remoteJID: '5511999999999@s.whatsapp.net' }
          }
        }
      }

      key = described_class.extract_delete_key(data, event: 'MESSAGE')

      expect(key[:id]).to eq('REV-TYPENAME')
    end

    it 'returns nil for regular text messages' do
      payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_inbound.json').read)

      key = described_class.extract_delete_key(payload['data'], event: 'MESSAGE')

      expect(key).to be_nil
    end
  end
end
