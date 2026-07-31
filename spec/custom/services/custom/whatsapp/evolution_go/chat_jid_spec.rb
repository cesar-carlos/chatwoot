# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::ChatJid do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'evolution_go', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999999999') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      source_id: 'MSG-1',
      content_attributes: {
        'evolution_go_remote_jid' => '5511888888888@s.whatsapp.net'
      }
    )
  end

  it 'prefers contact @lid identifier over a stale PN remote_jid' do
    contact.update!(identifier: '123456789012345@lid')

    expect(described_class.for_message(message)).to eq('123456789012345@lid')
  end

  it 'prefers message-level @lid remote_jid when present' do
    message.update!(
      content_attributes: { 'evolution_go_remote_jid' => '999888777666555@lid' }
    )
    contact.update!(identifier: '123456789012345@lid')

    expect(described_class.for_message(message)).to eq('999888777666555@lid')
  end

  it 'falls back to message PN remote_jid when no LID exists' do
    expect(described_class.for_message(message)).to eq('5511888888888@s.whatsapp.net')
  end

  it 'falls back to contact_inbox phone JID' do
    message.update!(content_attributes: {})

    expect(described_class.for_message(message)).to eq('5511999999999@s.whatsapp.net')
  end

  it 'prefers contact stored PN remote_jid over WITH-9 source_id for outgoing' do
    contact.update!(
      additional_attributes: {
        Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY =>
          '555126346969@s.whatsapp.net'
      }
    )
    contact_inbox.update!(source_id: '5551926346969')
    outgoing = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      content: 'welcome',
      content_attributes: {}
    )

    expect(described_class.for_message(outgoing)).to eq('555126346969@s.whatsapp.net')
  end

  it 'prefers latest inbound @lid when outgoing has no attrs' do
    message.update!(
      content_attributes: { 'evolution_go_remote_jid' => '999888777666555@lid' }
    )
    outgoing = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      content: 'welcome',
      content_attributes: {}
    )

    expect(described_class.for_message(outgoing)).to eq('999888777666555@lid')
  end

  describe '.for_conversation' do
    it 'prefers contact @lid identifier' do
      contact.update!(identifier: '123456789012345@lid')

      expect(described_class.for_conversation(conversation)).to eq('123456789012345@lid')
    end

    it 'falls back to latest inbound remote_jid' do
      message # ensure inbound exists

      expect(described_class.for_conversation(conversation)).to eq('5511888888888@s.whatsapp.net')
    end

    it 'falls back to contact_inbox phone JID' do
      message.destroy!

      expect(described_class.for_conversation(conversation)).to eq('5511999999999@s.whatsapp.net')
    end
  end
end
