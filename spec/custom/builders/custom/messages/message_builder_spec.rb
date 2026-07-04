# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Messages::MessageBuilder do
  describe 'Wavoip voice-only inbox' do
    let(:account) { create(:account) }
    let(:channel) { create(:channel_wavoip, account: account) }
    let(:inbox) { channel.inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:agent) { create(:user, account: account) }

    before do
      account.enable_features!('channel_voice', 'channel_wavoip')
    end

    it 'rejects outgoing public text messages' do
      expect do
        described_class.new(agent, conversation, { content: 'Hello', message_type: 'outgoing' }).perform
      end.to raise_error(CustomExceptions::Wavoip::VoiceOnlyInbox)
    end

    it 'rejects outgoing public attachment-only messages' do
      expect do
        described_class.new(
          agent,
          conversation,
          { content: '', message_type: 'outgoing', attachments: ['signed-blob-id'] }
        ).perform
      end.to raise_error(CustomExceptions::Wavoip::VoiceOnlyInbox)
    end

    it 'allows private notes' do
      message = described_class.new(
        agent,
        conversation,
        { content: 'Internal note', message_type: 'outgoing', private: true }
      ).perform

      expect(message).to be_persisted
      expect(message.private).to be true
    end

    it 'allows voice_call system messages' do
      message = described_class.new(
        nil,
        conversation,
        {
          content: I18n.t('conversations.messages.voice_call.wavoip'),
          message_type: 'outgoing',
          content_type: 'voice_call',
          content_attributes: { 'data' => { 'status' => 'ringing' } }
        }
      ).perform

      expect(message).to be_persisted
      expect(message.content_type).to eq('voice_call')
    end
  end
end
