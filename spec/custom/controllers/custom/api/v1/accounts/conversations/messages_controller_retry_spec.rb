# frozen_string_literal: true

require 'rails_helper'

describe 'Custom MessagesController#retry', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:parent) { create(:message, account: account, conversation: conversation, source_id: 'wamid.ABC') }
  let(:message) do
    create(
      :message,
      account: account,
      conversation: conversation,
      status: :failed,
      content_attributes: {
        external_error: 'send failed',
        in_reply_to: parent.id,
        in_reply_to_external_id: parent.source_id
      }
    )
  end

  before do
    create(:inbox_member, inbox: inbox, user: agent)
  end

  it 'clears external_error but keeps in_reply_to attributes' do
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/retry",
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:success)
    message.reload
    expect(message.status).to eq('sent')
    expect(message.content_attributes['external_error']).to be_nil
    expect(message.content_attributes['in_reply_to']).to eq(parent.id)
    expect(message.content_attributes['in_reply_to_external_id']).to eq(parent.source_id)
  end
end
