require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::ConversationWorkflowRulesController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:headers) { administrator.create_new_auth_token }
  let(:base_url) { "/api/v1/accounts/#{account.id}/conversation_workflow_rules" }

  describe 'GET /conversation_workflow_rules' do
    it 'returns workflow rules for administrators' do
      rule = ConversationWorkflowRule.create!(
        account: account,
        name: 'Test',
        trigger_type: :conversation_inactivity,
        duration_minutes: 60,
        resolve_on_match: true
      )

      get base_url, headers: headers

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.first['id']).to eq(rule.id)
    end
  end

  describe 'POST /conversation_workflow_rules' do
    it 'creates a workflow rule' do
      post base_url,
           params: {
             name: 'New rule',
             trigger_type: 'conversation_inactivity',
             duration_minutes: 60,
             active: true,
             resolve_on_match: true
           },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:created)
      expect(account.conversation_workflow_rules.count).to eq(1)
    end

    it 'returns legacy warning when auto resolve is still active' do
      account.update!(auto_resolve_after: 60)

      post base_url,
           params: {
             name: 'New rule',
             trigger_type: 'conversation_inactivity',
             duration_minutes: 60,
             active: true
           },
           headers: headers,
           as: :json

      expect(response.parsed_body['legacy_auto_resolve_active']).to be(true)
    end
  end

  describe 'POST /conversation_workflow_rules/reorder' do
    it 'updates positions' do
      first_rule = ConversationWorkflowRule.create!(
        account: account,
        name: 'First',
        trigger_type: :conversation_inactivity,
        duration_minutes: 60,
        position: 0,
        resolve_on_match: true
      )
      second_rule = ConversationWorkflowRule.create!(
        account: account,
        name: 'Second',
        trigger_type: :conversation_inactivity,
        duration_minutes: 120,
        position: 1,
        resolve_on_match: true
      )

      post "#{base_url}/reorder",
           params: { rules: [{ id: second_rule.id, position: 0 }, { id: first_rule.id, position: 1 }] },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:success)
      expect(second_rule.reload.position).to eq(0)
      expect(first_rule.reload.position).to eq(1)
    end
  end

  describe 'POST /conversation_workflow_rules/migrate_legacy' do
    it 'migrates legacy auto resolve settings' do
      account.update!(auto_resolve_after: 60, auto_resolve_message: 'Bye')

      post "#{base_url}/migrate_legacy", headers: headers

      expect(response).to have_http_status(:success)
      expect(account.reload.workflow_rules_migrated?).to be(true)
    end
  end
end
