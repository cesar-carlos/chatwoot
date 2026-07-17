# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::MessageEditPayloadExtractor do
  describe '.extract_edit_payload' do
    it 'extracts edit from MESSAGE protocol payload (IsEdit + conversation)' do
      payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_edit.json').read)

      result = described_class.extract_edit_payload(payload['data'], event: 'MESSAGE')

      aggregate_failures do
        # Original id is protocolMessage.key.ID — not Info.ID of the edit event.
        expect(result[:key][:id]).to eq('AC9A902ED6D1458D0A9FB5C4023580E7')
        expect(result[:edited_body]).to eq('Texto atualizado pelo cliente')
        expect(result[:encrypted_edit]).to be_nil
      end
    end

    it 'extracts API echo edit with extendedTextMessage text' do
      payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_edit_api_echo.json').read)

      result = described_class.extract_edit_payload(payload['data'], event: 'MESSAGE')

      aggregate_failures do
        expect(result[:key][:id]).to eq('3EB0ORIGINALMSGID0001')
        expect(result[:key][:fromMe]).to be(true)
        expect(result[:edited_body]).to eq('Texto corrigido pela API')
      end
    end

    it 'extracts edit when only typeName is present (no numeric type)' do
      data = {
        IsEdit: true,
        messageType: 'edit',
        Message: {
          protocolMessage: {
            typeName: 'MESSAGE_EDIT',
            key: { ID: 'ONLY-TYPENAME', fromMe: false, remoteJID: '5511999999999@s.whatsapp.net' },
            editedMessage: { conversation: 'via typeName only' }
          }
        }
      }

      result = described_class.extract_edit_payload(data, event: 'MESSAGE')

      expect(result[:key][:id]).to eq('ONLY-TYPENAME')
      expect(result[:edited_body]).to eq('via typeName only')
    end

    it 'extracts edit from explicit MESSAGES_EDITED event' do
      data = {
        key: { id: 'MSG-EDIT-1', remoteJid: '5511999999999@s.whatsapp.net', fromMe: false },
        editedMessage: { conversation: 'Updated body' }
      }

      result = described_class.extract_edit_payload(data, event: 'MESSAGES_EDITED')

      expect(result[:key][:id]).to eq('MSG-EDIT-1')
      expect(result[:edited_body]).to eq('Updated body')
    end

    it 'detects Evolution Go secretEncryptedMessage edit envelopes' do
      payload = JSON.parse(
        Rails.root.join('spec/fixtures/evolution_go/message_edit_secret_encrypted.json').read
      )

      result = described_class.extract_edit_payload(payload['data'], event: 'MESSAGE')

      aggregate_failures do
        expect(result[:key][:id]).to eq('ACE6C86D3693CAD6E8EDEA53051A87BA')
        expect(result[:edited_body]).to be_nil
        expect(result[:encrypted_edit]).to be(true)
      end
    end

    it 'returns nil for regular text messages' do
      payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_inbound.json').read)

      result = described_class.extract_edit_payload(payload['data'], event: 'MESSAGE')

      expect(result).to be_nil
    end

    it 'does not treat revoke Info.Edit as an edit envelope' do
      payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_revoke.json').read)

      result = described_class.extract_edit_payload(payload['data'], event: 'MESSAGE')

      expect(result).to be_nil
    end

    it 'returns nil for IsEdit flag without key or body (no stub hash)' do
      data = {
        Info: { Edit: '1', ID: 'NEW-EVENT' },
        IsEdit: true,
        messageType: 'edit',
        Message: {}
      }

      result = described_class.extract_edit_payload(data, event: 'MESSAGE')

      expect(result).to be_nil
    end
  end
end
