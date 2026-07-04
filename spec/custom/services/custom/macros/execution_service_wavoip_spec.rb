# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Macros::ExecutionService do
  describe 'send_message on Wavoip inbox' do
    let(:account) { create(:account) }
    let(:channel) { create(:channel_wavoip, account: account) }
    let(:inbox) { channel.inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:user) { create(:user, account: account) }
    let(:macro) do
      create(
        :macro,
        account: account,
        actions: [{ 'action_name' => 'send_message', 'action_params' => ['Macro hello'] }]
      )
    end

    before do
      account.enable_features!('channel_voice', 'channel_wavoip')
    end

    it 'does not create a public message and does not raise' do
      expect do
        described_class.new(macro, conversation, user).perform
      end.not_to raise_error

      expect(conversation.messages.chat.count).to eq(0)
    end
  end
end
