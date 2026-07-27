# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::JidResolver do
  subject(:resolver) { described_class.new('merge_brazil_contacts' => false) }

  describe '#resolve_message_jid' do
    it 'keeps group JID when addressingMode is lid and remoteJidAlt is a participant PN' do
      jid = resolver.resolve_message_jid(
        'remoteJid' => '120363012345678901@g.us',
        'remoteJidAlt' => '5511777777777@s.whatsapp.net',
        'addressingMode' => 'lid'
      )

      expect(jid).to eq('120363012345678901@g.us')
    end
  end

  describe '#phone_from_message_key' do
    it 'resolves LID messages using remoteJidAlt' do
      phone = resolver.phone_from_message_key(
        'remoteJid' => '242532642504895@lid',
        'remoteJidAlt' => '556696971841@s.whatsapp.net',
        'addressingMode' => 'lid'
      )

      expect(phone).to eq('556696971841')
    end

    it 'does not resolve a phone from group JID keys even with LID alt' do
      phone = resolver.phone_from_message_key(
        'remoteJid' => '120363012345678901@g.us',
        'remoteJidAlt' => '5511777777777@s.whatsapp.net',
        'addressingMode' => 'lid'
      )

      expect(phone).to be_nil
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

    it 'returns full group JID for group status keys' do
      recipient = resolver.recipient_id_for_status('120363123456789012@g.us')

      expect(recipient).to eq('120363123456789012@g.us')
    end
  end

  describe '#phone_from_jid' do
    it 'does not fabricate a phone number from bare LID JIDs' do
      expect(resolver.phone_from_jid('242532642504895@lid')).to be_nil
    end

    it 'strips device suffix from WhatsApp device JIDs' do
      expect(resolver.phone_from_jid('5511777777777:38@s.whatsapp.net')).to eq('5511777777777')
    end

    it 'does not treat group JIDs as phone numbers' do
      expect(resolver.phone_from_jid('120363012345678901@g.us')).to be_nil
    end
  end
end
