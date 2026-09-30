require 'rails_helper'

RSpec.describe 'Custom role authorization for Linear conversation actions', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:headers) { agent.create_new_auth_token }

  before do
    create(:integrations_hook, :linear, account: account)
    create(:inbox_member, inbox: inbox, user: agent)
    account.account_users.find_by!(user: agent).update!(
      custom_role: create(:custom_role, account: account, permissions: [])
    )
  end

  {
    create_issue: :post,
    link_issue: :post,
    unlink_issue: :post,
    linked_issues: :get
  }.each do |action, verb|
    it "rejects #{action} when the custom role cannot view the conversation" do
      params = {
        conversation_id: conversation.display_id,
        team_id: 'team-1',
        issue_id: 'ISSUE-1',
        link_id: 'link-1',
        title: 'Issue'
      }

      public_send(
        verb,
        "/api/v1/accounts/#{account.id}/integrations/linear/#{action}",
        params: params,
        headers: headers,
        as: :json
      )

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
