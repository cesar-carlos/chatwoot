require 'rails_helper'

RSpec.describe ConversationWorkflowRuleExecution do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:rule) do
    create_workflow_rule!(
      account: account,
      name: 'Inactivity',
      trigger_type: :conversation_inactivity
    )
  end

  describe '.record!' do
    it 'creates execution with last activity epoch' do
      described_class.record!(
        rule: rule,
        conversation: conversation,
        last_activity_epoch: 1_700_000_000
      )

      expect(described_class.count).to eq(1)
    end

    it 'raises on duplicate dedup key' do
      described_class.record!(
        rule: rule,
        conversation: conversation,
        last_activity_epoch: 1_700_000_000
      )

      expect do
        described_class.record!(
          rule: rule,
          conversation: conversation,
          last_activity_epoch: 1_700_000_000
        )
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '.release!' do
    it 'removes execution by waiting_since epoch' do
      agent_rule = create_workflow_rule!(
        account: account,
        trigger_type: :agent_no_reply
      )
      conversation.update!(waiting_since: 1.hour.ago)
      described_class.record!(
        rule: agent_rule,
        conversation: conversation,
        waiting_since_epoch: conversation.waiting_since.to_i
      )

      described_class.release!(rule: agent_rule, conversation: conversation)

      expect(described_class.count).to eq(0)
    end
  end

  describe '.clear_unassigned_too_long_for!' do
    let(:unassigned_rule) do
      create_workflow_rule!(
        account: account,
        name: 'Unassigned',
        trigger_type: :unassigned_too_long
      )
    end

    it 'removes executions for unassigned_too_long rules on the conversation' do
      described_class.record!(
        rule: unassigned_rule,
        conversation: conversation,
        last_activity_epoch: conversation.created_at.to_i
      )

      described_class.clear_unassigned_too_long_for!(conversation: conversation)

      expect(described_class.count).to eq(0)
    end
  end
end
