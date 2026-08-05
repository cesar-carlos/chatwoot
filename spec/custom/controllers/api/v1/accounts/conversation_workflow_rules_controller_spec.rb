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

    it 'rejects active inactivity rules while legacy auto resolve is still active' do
      account.update!(auto_resolve_after: 60)

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

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.conversation_workflow_rules.count).to eq(0)
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

  describe 'POST /conversation_workflow_rules/preview_count' do
    it 'returns a count for administrators' do
      post "#{base_url}/preview_count",
           params: {
             trigger_type: 'conversation_inactivity',
             duration_minutes: 60,
             resolve_on_match: true
           },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to have_key('count')
    end
  end

  describe 'GET /conversation_workflow_rules/:id/activity' do
    it 'returns recent executions and skips' do
      rule = ConversationWorkflowRule.create!(
        account: account,
        name: 'Activity rule',
        trigger_type: :agent_no_reply,
        duration_minutes: 15,
        actions: [{ 'action_name' => 'add_label', 'action_params' => ['vip'] }]
      )
      conversation = create(:conversation, account: account)
      ConversationWorkflowRuleExecution.record!(
        rule: rule,
        conversation: conversation,
        waiting_since_epoch: Time.current.to_i
      )
      ConversationWorkflowRuleSkip.record!(
        rule: rule,
        action_name: 'send_message_to_contact',
        reason: 'blank_message'
      )

      get "#{base_url}/#{rule.id}/activity", headers: headers

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['executions'].first['conversation_id']).to eq(conversation.id)
      expect(body['skips'].first['reason']).to eq('blank_message')
    end
  end

  describe 'GET /conversation_workflow_rules index recent_skips_count' do
    it 'includes recent_skips_count' do
      rule = ConversationWorkflowRule.create!(
        account: account,
        name: 'Skip count',
        trigger_type: :agent_no_reply,
        duration_minutes: 15,
        actions: [{ 'action_name' => 'add_label', 'action_params' => ['vip'] }]
      )
      ConversationWorkflowRuleSkip.record!(
        rule: rule,
        action_name: 'send_message_to_contact',
        reason: 'blank_message'
      )

      get base_url, headers: headers

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.first['recent_skips_count']).to eq(1)
    end
  end
end
