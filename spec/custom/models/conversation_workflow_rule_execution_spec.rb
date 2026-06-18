require 'rails_helper'

RSpec.describe ConversationWorkflowRuleExecution do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:rule) do
    ConversationWorkflowRule.create!(
      account: account,
      name: 'Inactivity',
      trigger_type: :conversation_inactivity,
      duration_minutes: 60
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

  describe '.already_executed?' do
    it 'returns true when waiting_since epoch matches' do
      described_class.record!(
        rule: rule,
        conversation: conversation,
        waiting_since_epoch: 1_700_000_000
      )

      expect(
        described_class.already_executed?(
          rule: rule,
          conversation: conversation,
          waiting_since_epoch: 1_700_000_000
        )
      ).to be(true)
    end
  end
end
