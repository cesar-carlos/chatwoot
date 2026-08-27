# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::JidResolver do
  subject(:resolver) { described_class.new('merge_brazil_contacts' => false) }

  describe '#addressing_jid' do
    it 'keeps raw @lid remoteJid even when a phone alt is present' do
      jid = resolver.addressing_jid(
        'remoteJid' => '123456789012345@lid',
        'remoteJidAlt' => '5511999999999@s.whatsapp.net',
        'addressingMode' => 'lid'
      )

      expect(jid).to eq('123456789012345@lid')
    end

    it 'keeps group JID' do
      jid = resolver.addressing_jid(
        'remoteJid' => '120363012345678901@g.us',
        'remoteJidAlt' => '5511777777777@s.whatsapp.net',
        'addressingMode' => 'lid'
      )

      expect(jid).to eq('120363012345678901@g.us')
    end

    it 'uses remoteJidAlt when only the alt is @lid' do
      jid = resolver.addressing_jid(
        'remoteJid' => '5511999999999@s.whatsapp.net',
        'remoteJidAlt' => '123456789012345@lid'
      )

      expect(jid).to eq('123456789012345@lid')
    end
  end

  describe '.merge_addressing_jid' do
    it 'promotes a stored PN to incoming @lid' do
      merged = described_class.merge_addressing_jid(
        '5511999999999@s.whatsapp.net',
        '123456789012345@lid'
      )

      expect(merged).to eq('123456789012345@lid')
    end

    it 'does not regress a stored @lid to a PN' do
      merged = described_class.merge_addressing_jid(
        '123456789012345@lid',
        '5511999999999@s.whatsapp.net'
      )

      expect(merged).to eq('123456789012345@lid')
    end
  end
end
