require 'rails_helper'

RSpec.describe Custom::ConversationWorkflow::ScopeMatcher do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }

  def matcher_for(rule, conversation)
    described_class.new(rule: rule, conversation: conversation)
  end

  describe '#matches?' do
    it 'matches open inactivity conversations in allowed inbox' do
      rule = create_workflow_rule!(
        account: account,
        name: 'Inactivity',
        trigger_type: :conversation_inactivity,
        inbox_ids: [inbox.id]
      )
      conversation = create(:conversation, account: account, inbox: inbox, status: :open)

      expect(matcher_for(rule, conversation).matches?).to be(true)
    end

    it 'rejects inactivity when inbox is filtered out' do
      rule = create_workflow_rule!(
        account: account,
        name: 'Inactivity',
        trigger_type: :conversation_inactivity,
        inbox_ids: [other_inbox.id]
      )
      conversation = create(:conversation, account: account, inbox: inbox, status: :open)

      expect(matcher_for(rule, conversation).matches?).to be(false)
    end

    it 'matches pending agent no reply when status allowed' do
      rule = create_workflow_rule!(
        account: account,
        name: 'No reply',
        trigger_type: :agent_no_reply,
        options: { 'statuses' => %w[pending] }
      )
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        status: :pending,
        waiting_since: 2.hours.ago
      )

      expect(matcher_for(rule, conversation).matches?).to be(true)
    end

    it 'rejects agent no reply when first reply exists and required' do
      rule = create_workflow_rule!(
        account: account,
        name: 'No reply',
        trigger_type: :agent_no_reply,
        options: { 'require_no_first_reply' => true }
      )
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        waiting_since: 2.hours.ago,
        first_reply_created_at: 1.hour.ago
      )

      expect(matcher_for(rule, conversation).matches?).to be(false)
    end
  end
end
