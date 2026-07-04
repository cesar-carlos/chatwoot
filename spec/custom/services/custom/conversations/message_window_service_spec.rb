# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversations::MessageWindowService do
  describe 'on Wavoip channels' do
    let(:account) { create(:account) }
    let(:channel) { create(:channel_wavoip, account: account) }
    let(:inbox) { channel.inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    before do
      account.enable_features!('channel_voice', 'channel_wavoip')
    end

    it 'returns can_reply? false for voice-only inbox' do
      service = described_class.new(conversation)

      expect(service.can_reply?).to be false
    end
  end
end
