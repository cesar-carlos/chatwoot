# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::MessageEditPayloadExtractor do
  describe '.extract_edit_payload' do
    it 'extracts edit from MESSAGE protocol payload' do
      payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_edit.json').read)

      result = described_class.extract_edit_payload(payload['data'], event: 'MESSAGE')

      expect(result[:key][:id]).to eq('3EB0EDITEDMSG123')
      expect(result[:edited_body]).to eq('Texto atualizado pelo cliente')
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

    it 'returns nil for regular text messages' do
      payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_inbound.json').read)

      result = described_class.extract_edit_payload(payload['data'], event: 'MESSAGE')

      expect(result).to be_nil
    end
  end
end
