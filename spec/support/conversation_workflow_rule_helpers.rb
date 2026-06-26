module ConversationWorkflowRuleHelpers
  def build_workflow_rule_attrs(overrides = {})
    trigger_type = (overrides[:trigger_type] || :conversation_inactivity).to_s
    base = {
      name: 'Test rule',
      duration_minutes: 60,
      conditions: [],
      actions: []
    }

    outcome =
      if trigger_type == 'conversation_inactivity'
        { resolve_on_match: true }
      else
        { actions: [{ 'action_name' => 'add_label', 'action_params' => ['test'] }] }
      end

    base.merge(outcome).merge(overrides)
  end

  def create_workflow_rule!(account:, **overrides)
    ConversationWorkflowRule.create!(build_workflow_rule_attrs(overrides).merge(account: account))
  end
end

RSpec.configure do |config|
  config.include ConversationWorkflowRuleHelpers
end
