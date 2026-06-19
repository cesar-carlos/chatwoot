require 'rails_helper'

RSpec.describe 'Conversation message search API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:headers) { agent.create_new_auth_token }
  let(:endpoint) do
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/search"
  end

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    create(
      :message,
      conversation: conversation,
      account: account,
      inbox: inbox,
      content: 'contract details here',
      message_type: :incoming,
      sender: conversation.contact
    )
  end

  describe 'GET /messages/search' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get endpoint, params: { q: 'contract' }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns matching messages with meta' do
        get endpoint, params: { q: 'contract' }, headers: headers, as: :json

        expect(response).to have_http_status(:success)

        body = response.parsed_body
        expect(body['payload'].length).to eq(1)
        expect(body['payload'].first['content']).to include('contract')
        expect(body['payload'].first['matched_on']).to eq('content')
        expect(body['meta']).to include(
          'current_page' => 1,
          'has_more' => false,
          'max_results' => Custom::ConversationMessageSearchFinder::MAX_RESULTS
        )
        expect(body['meta']['search_engine']).to be_present
      end

      it 'returns unprocessable entity for short queries' do
        get endpoint, params: { q: 'c' }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('between 2 and 200')
      end

      it 'returns unprocessable entity for invalid page' do
        get endpoint, params: { q: 'contract', page: 0 }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('positive integer')
      end

      it 'returns too many requests when rate limited' do
        key = "conversation_message_search:#{agent.id}:#{conversation.id}"
        Rails.cache.write(key, Custom::Api::V1::Accounts::Conversations::MessagesController::SEARCH_RATE_LIMIT,
                          expires_in: 1.minute)

        get endpoint, params: { q: 'contract' }, headers: headers, as: :json

        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body['error']).to include('Too many search requests')
      end

      it 'filters results by from=agent' do
        agent_user = create(:user, account: account, role: :agent)
        create(
          :message,
          conversation: conversation,
          account: account,
          inbox: inbox,
          content: 'agent contract note',
          message_type: :outgoing,
          sender: agent_user
        )

        get endpoint, params: { q: 'contract', from: 'agent' }, headers: headers, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].map { |m| m['sender']['type'] }.uniq).to eq(['user'])
      end

      it 'returns page 2 with has_more on first page when many matches exist' do
        16.times do |index|
          create(
            :message,
            conversation: conversation,
            account: account,
            inbox: inbox,
            content: "contract batch #{index}",
            message_type: :incoming,
            sender: conversation.contact,
            created_at: (index + 1).minutes.ago
          )
        end

        get endpoint, params: { q: 'contract', page: 1 }, headers: headers, as: :json
        expect(response.parsed_body['meta']['has_more']).to be(true)

        get endpoint, params: { q: 'contract', page: 2 }, headers: headers, as: :json
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].length).to be >= 1
      end

      it 'returns not found for unknown conversation' do
        missing_endpoint = "/api/v1/accounts/#{account.id}/conversations/999999/messages/search"

        get missing_endpoint, params: { q: 'contract' }, headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
