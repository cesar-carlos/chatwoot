require 'rails_helper'

RSpec.describe 'Notification history authorization', type: :request do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account, allow_auto_assign: false) }
  let(:user) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, team: team) }
  let!(:notification) { create(:notification, user: user, account: account, primary_actor: conversation) }

  before do
    team.members << user
    team.team_members.where(user: user).destroy_all
  end

  it 'omits inaccessible payloads and counts from the index and unread endpoint' do
    get "/api/v1/accounts/#{account.id}/notifications", headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'payload')).to be_empty
    expect(response.parsed_body.dig('data', 'meta')).to include('count' => 0, 'unread_count' => 0)
    get "/api/v1/accounts/#{account.id}/notifications/unread_count", headers: user.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq(0)
  end

  it 'does not reveal or mutate an inaccessible notification via the individual endpoint' do
    patch "/api/v1/accounts/#{account.id}/notifications/#{notification.id}", headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(notification.reload.read_at).to be_nil
  end

  it 'does not mark inaccessible notifications during a bulk read' do
    post "/api/v1/accounts/#{account.id}/notifications/read_all", headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(notification.reload.read_at).to be_nil
  end

  it 'does not disclose the internal ledger through the messages API when conversation access is restored' do
    create(:inbox_member, user: user, inbox: conversation.inbox)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
        headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('meta', 'additional_attributes')).not_to have_key('team_notification_transition')
    expect(conversation.reload.additional_attributes).to have_key('team_notification_transition')
  end
end
