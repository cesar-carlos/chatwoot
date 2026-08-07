require 'rails_helper'

RSpec.describe 'Notifications API custom role inbox view permission', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:account_user) { agent.account_users.find_by(account: account) }

  describe 'GET /api/v1/accounts/{account.id}/notifications' do
    it 'returns success when custom role includes inbox_view_manage' do
      custom_role = create(:custom_role, account: account, permissions: ['inbox_view_manage'])
      account_user.update!(custom_role: custom_role)

      get "/api/v1/accounts/#{account.id}/notifications",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
    end

    it 'returns unauthorized when custom role lacks inbox_view_manage' do
      custom_role = create(:custom_role, account: account, permissions: ['conversation_participating_manage'])
      account_user.update!(custom_role: custom_role)

      get "/api/v1/accounts/#{account.id}/notifications",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/notifications/unread_count' do
    it 'returns unauthorized when custom role lacks inbox_view_manage' do
      custom_role = create(:custom_role, account: account, permissions: ['contact_manage'])
      account_user.update!(custom_role: custom_role)

      get "/api/v1/accounts/#{account.id}/notifications/unread_count",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
