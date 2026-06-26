require 'rails_helper'

RSpec.describe Custom::ConversationWorkflow::AutomationEventDispatcher do
  subject(:dispatcher) { described_class.new(rule: workflow_rule, conversation: conversation) }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      status: :open,
      waiting_since: 2.hours.ago
    )
  end
  let(:workflow_rule) do
    create_workflow_rule!(
      account: account,
      name: 'Inactivity rule',
      trigger_type: :conversation_inactivity
    )
  end

  it 'runs matching automation rules for the synthetic event' do
    automation_rule = create(
      :automation_rule,
      account: account,
      event_name: 'conversation_inactivity_threshold',
      active: true,
      conditions: []
    )
    action_service = instance_double(AutomationRules::ActionService, perform: true)
    allow(AutomationRules::ActionService).to receive(:new).and_return(action_service)

    dispatcher.perform

    expect(AutomationRules::ActionService).to have_received(:new).with(
      automation_rule,
      account,
      conversation
    )
    expect(action_service).to have_received(:perform)
  end

  it 'skips automation rules that fail conditions' do
    create(
      :automation_rule,
      account: account,
      event_name: 'conversation_inactivity_threshold',
      active: true,
      conditions: [
        {
          'attribute_key' => 'status',
          'filter_operator' => 'equal_to',
          'values' => ['resolved'],
          'query_operator' => 'AND'
        }
      ]
    )
    allow(AutomationRules::ActionService).to receive(:new)

    dispatcher.perform

    expect(AutomationRules::ActionService).not_to have_received(:new)
  end
end
