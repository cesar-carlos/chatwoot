require 'rails_helper'

RSpec.describe DeleteObjectJob, type: :job do
  describe 'conversation workflow rule executions' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let!(:rule) { create_workflow_rule!(account: account) }

    before do
      ConversationWorkflowRuleExecution.record!(
        rule: rule,
        conversation: conversation,
        last_activity_epoch: conversation.last_activity_at.to_i
      )
    end

    it 'deletes executions when destroying a conversation' do
      expect do
        conversation.destroy!
      end.to change(ConversationWorkflowRuleExecution, :count).by(-1)
    end

    it 'purges executions before account destroy via DeleteObjectJob' do
      expect do
        described_class.perform_now(account)
      end.to change(ConversationWorkflowRuleExecution, :count).by(-1)

      expect { account.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
