require 'rails_helper'

RSpec.describe ConversationWorkflowRuleSkip, type: :model do
  let(:account) { create(:account) }
  let(:rule) do
    ConversationWorkflowRule.create!(
      account: account,
      name: 'Skip rule',
      trigger_type: :agent_no_reply,
      duration_minutes: 15,
      actions: [{ 'action_name' => 'add_label', 'action_params' => ['vip'] }]
    )
  end

  describe '.record!' do
    it 'persists a skip and prunes old rows beyond the limit' do
      described_class::MAX_PER_RULE.times do |index|
        described_class.record!(
          rule: rule,
          action_name: 'send_message_to_contact',
          reason: "reason_#{index}"
        )
      end

      described_class.record!(
        rule: rule,
        action_name: 'send_message_to_contact',
        reason: 'newest'
      )

      expect(described_class.where(conversation_workflow_rule: rule).count).to eq(described_class::MAX_PER_RULE)
      expect(described_class.where(conversation_workflow_rule: rule).order(created_at: :desc).first.reason).to eq('newest')
    end
  end

  describe '.recent_count_by_rule_ids' do
    it 'counts skips from the last 24 hours' do
      described_class.record!(
        rule: rule,
        action_name: 'send_message_to_contact',
        reason: 'blank_message'
      )
      described_class.create!(
        conversation_workflow_rule: rule,
        action_name: 'send_message_to_contact',
        reason: 'old',
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )

      counts = described_class.recent_count_by_rule_ids([rule.id])
      expect(counts[rule.id]).to eq(1)
    end
  end
end
