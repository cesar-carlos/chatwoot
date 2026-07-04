# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Wavoip Conversation Messages API', type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
    create(:inbox_member, inbox: inbox, user: agent)
  end

  describe 'POST /api/v1/accounts/:account_id/conversations/:conversation_id/messages' do
    it 'returns 403 for outgoing public text on voice-only inbox' do
      post api_v1_account_conversation_messages_url(
        account_id: account.id,
        conversation_id: conversation.display_id
      ),
           params: { content: 'Hello customer' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['message']).to eq(I18n.t('errors.wavoip.voice_only_inbox'))
      expect(conversation.messages.chat.count).to eq(0)
    end

    it 'allows private notes' do
      post api_v1_account_conversation_messages_url(
        account_id: account.id,
        conversation_id: conversation.display_id
      ),
           params: { content: 'Internal note', private: true },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.messages.count).to eq(1)
      expect(conversation.messages.first.private).to be true
    end
  end

  describe 'POST retry on voice-only inbox' do
    let!(:failed_message) do
      message = build(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        private: false,
        status: :failed,
        content: 'Failed delivery'
      )
      message.save(validate: false)
      message
    end

    it 'returns 403 when retrying a public message' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{failed_message.id}/retry",
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['message']).to eq(I18n.t('errors.wavoip.voice_only_inbox'))
    end
  end
end
