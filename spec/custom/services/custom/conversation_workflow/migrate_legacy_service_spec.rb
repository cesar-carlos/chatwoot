require 'rails_helper'

RSpec.describe Custom::ConversationWorkflow::MigrateLegacyService do
  subject(:service) { described_class.new(account) }

  let(:account) { create(:account) }

  before do
    account.update!(
      auto_resolve_after: 120,
      auto_resolve_message: 'Closing due to inactivity',
      auto_resolve_ignore_waiting: true,
      auto_resolve_label: 'inativos'
    )
  end

  it 'creates an inactivity rule and marks the account as migrated', :aggregate_failures do
    service.perform

    expect(account.reload.workflow_rules_migrated?).to be(true)
    rule = account.conversation_workflow_rules.first
    expect(rule.name).to eq('Auto-resolve (migrated)')
    expect(rule.trigger_type).to eq('conversation_inactivity')
    expect(rule.duration_minutes).to eq(120)
    expect(rule.message).to eq('Closing due to inactivity')
    expect(rule.ignore_waiting).to be(true)
    expect(rule.resolve_on_match).to be(true)
    expect(rule.actions).to eq([{ 'action_name' => 'add_label', 'action_params' => ['inativos'] }])
  end

  it 'skips when already migrated' do
    account.update!(settings: account.settings.merge('workflow_rules_migrated_at' => Time.current.iso8601))

    expect { service.perform }.not_to change(ConversationWorkflowRule, :count)
  end

  it 'skips when auto_resolve_after is blank' do
    account.update!(auto_resolve_after: nil)

    expect { service.perform }.not_to change(ConversationWorkflowRule, :count)
    expect(account.reload.workflow_rules_migrated?).to be(false)
  end
end
