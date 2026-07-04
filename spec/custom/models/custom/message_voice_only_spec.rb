# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Message, type: :model do
  describe 'Wavoip voice-only inbox' do
    let(:account) { create(:account) }
    let(:channel) { create(:channel_wavoip, account: account) }
    let(:inbox) { channel.inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    before do
      account.enable_features!('channel_voice', 'channel_wavoip')
    end

    it 'rejects outgoing public text on create' do
      message = build(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        private: false,
        content: 'Hello'
      )

      expect(message).not_to be_valid
      expect(message.errors[:base]).to include(I18n.t('errors.wavoip.voice_only_inbox'))
    end

    it 'allows private notes' do
      message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        private: true,
        content: 'Internal note'
      )

      expect(message).to be_persisted
    end

    it 'allows voice_call system messages' do
      message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        private: false,
        content_type: :voice_call,
        content: I18n.t('conversations.messages.voice_call.wavoip')
      )

      expect(message).to be_persisted
    end

    it 'does not enqueue SendReplyJob for voice-only outgoing text channels' do
      expect do
        create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          message_type: :outgoing,
          private: true,
          content: 'Note only'
        )
      end.not_to have_enqueued_job(SendReplyJob)
    end
  end
end
