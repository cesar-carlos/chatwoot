require 'rails_helper'

RSpec.describe 'Custom conversation participation payload', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:participating_conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:other_conversation) { create(:conversation, account: account, inbox: inbox) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:conversation_participant, account: account, conversation: participating_conversation, user: agent)
  end

  it 'loads participation once for the whole collection and serializes the per-conversation flag' do
    sql_queries = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql_queries << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:cached]
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      get "/api/v1/accounts/#{account.id}/conversations",
          headers: agent.create_new_auth_token,
          as: :json
    end

    expect(response).to have_http_status(:success)
    participant_queries = sql_queries.grep(/FROM "conversation_participants"/)
    expect(participant_queries.size).to eq(1)

    payload = response.parsed_body.dig('data', 'payload').index_by { |item| item['id'] }
    expect(payload.dig(participating_conversation.display_id, 'meta', 'current_user_participating')).to be(true)
    expect(payload.dig(other_conversation.display_id, 'meta', 'current_user_participating')).to be(false)
  end
end
