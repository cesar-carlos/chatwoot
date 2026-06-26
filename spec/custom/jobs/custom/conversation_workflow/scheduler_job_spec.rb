require 'rails_helper'

RSpec.describe Custom::ConversationWorkflow::SchedulerJob do
  let!(:account) { create(:account) }

  it 'processes accounts with active workflow rules' do
    create_workflow_rule!(
      account: account,
      name: 'Inactivity',
      trigger_type: :conversation_inactivity,
      active: true
    )
    account.enable_features!(:auto_resolve_conversations)

    processor = instance_double(Custom::ConversationWorkflow::AccountProcessor, perform: true)
    allow(Custom::ConversationWorkflow::AccountProcessor).to receive(:new).with(account).and_return(processor)

    described_class.perform_now

    expect(processor).to have_received(:perform)
  end
end
