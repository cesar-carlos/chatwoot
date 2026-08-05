require 'rails_helper'

RSpec.describe ConversationWorkflowRule do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  describe 'validations' do
    it 'requires name and duration' do
      rule = described_class.new(account: account, duration_minutes: 60)
      expect(rule).not_to be_valid
      expect(rule.errors[:name]).to be_present
    end

    it 'rejects duration below minimum' do
      rule = build_rule(duration_minutes: 5)
      expect(rule).not_to be_valid
    end

    it 'rejects unsupported condition attributes' do
      rule = build_rule(conditions: [{ 'attribute_key' => 'browser_language', 'filter_operator' => 'equal_to', 'values' => ['en'] }])
      expect(rule).not_to be_valid
    end

    it 'rejects inbox ids outside account' do
      other_inbox = create(:inbox)
      rule = build_rule(inbox_ids: [other_inbox.id])
      expect(rule).not_to be_valid
    end

    it 'requires at least one outcome for inactivity rules' do
      rule = build_rule(resolve_on_match: false, message: '', actions: [])
      expect(rule).not_to be_valid
    end

    it 'requires actions for non-inactivity triggers' do
      rule = build_rule(trigger_type: :agent_no_reply, actions: [])
      expect(rule).not_to be_valid
    end
  end

  describe '#actions_attributes' do
    it 'excludes resolve_conversation for inactivity' do
      rule = build_rule(trigger_type: :conversation_inactivity)
      expect(rule.actions_attributes).not_to include('resolve_conversation')
    end

    it 'allows resolve_conversation for agent no reply' do
      rule = build_rule(trigger_type: :agent_no_reply)
      expect(rule.actions_attributes).to include('resolve_conversation')
    end
  end

  def build_rule(overrides = {})
    described_class.new(
      build_workflow_rule_attrs(overrides).merge(account: account)
    )
  end
end
