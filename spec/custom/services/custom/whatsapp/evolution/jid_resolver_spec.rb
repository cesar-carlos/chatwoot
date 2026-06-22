# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::JidResolver do
  subject(:resolver) { described_class.new('merge_brazil_contacts' => false) }

  describe '#phone_from_message_key' do
    it 'resolves LID messages using remoteJidAlt' do
      phone = resolver.phone_from_message_key(
        'remoteJid' => '242532642504895@lid',
        'remoteJidAlt' => '556696971841@s.whatsapp.net',
        'addressingMode' => 'lid'
      )

      expect(phone).to eq('556696971841')
    end
  end

  describe '#recipient_id_for_status' do
    it 'returns phone for direct chat status keys' do
      recipient = resolver.recipient_id_for_status(
        '5511999999999@s.whatsapp.net',
        { remoteJid: '5511999999999@s.whatsapp.net' }
      )

      expect(recipient).to eq('5511999999999')
    end

    it 'returns group id for group JIDs' do
      recipient = resolver.recipient_id_for_status('120363123456789012@g.us')

      expect(recipient).to eq('120363123456789012')
    end
  end
end
