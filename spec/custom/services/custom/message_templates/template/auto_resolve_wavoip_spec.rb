# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MessageTemplates::Template::AutoResolve do
  describe 'on Wavoip channels' do
    let(:account) { create(:account, auto_resolve_message: 'Resolved automatically') }
    let(:channel) { create(:channel_wavoip, account: account) }
    let(:inbox) { channel.inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    before do
      account.enable_features!('channel_voice', 'channel_wavoip')
    end

    it 'skips auto-resolve template on voice-only inbox' do
      expect do
        described_class.new(conversation: conversation).perform
      end.not_to change { conversation.messages.template.count }
    end
  end
end
