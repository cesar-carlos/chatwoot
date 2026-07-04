# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MessageTemplates::HookExecutionService do
  describe 'on Wavoip channels' do
    let(:account) { create(:account) }
    let(:channel) { create(:channel_wavoip, account: account) }
    let(:inbox) { channel.inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    before do
      account.enable_features!('channel_voice', 'channel_wavoip')
      inbox.update!(greeting_enabled: true, greeting_message: 'Welcome!')
    end

    it 'skips greeting template on voice-only inbox' do
      allow(MessageTemplates::Template::Greeting).to receive(:new)

      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)

      expect(MessageTemplates::Template::Greeting).not_to have_received(:new)
    end

    context 'when captain assistant is configured', if: defined?(Captain::Conversation::ResponseBuilderJob) do
      let(:assistant) { create(:captain_assistant, account: account) }

      before do
        create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
        conversation.update!(status: :pending)
      end

      it 'skips captain response on voice-only inbox' do
        expect(Captain::Conversation::ResponseBuilderJob).not_to receive(:perform_later)

        create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
      end
    end
  end
end
