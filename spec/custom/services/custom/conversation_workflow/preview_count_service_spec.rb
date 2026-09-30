require 'rails_helper'

RSpec.describe Custom::ConversationWorkflow::PreviewCountService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account) }

  before { account.enable_features!(:conversation_agent_no_reply_rules) }

  it 'excludes conversations that fail conditions' do
    matching = create(
      :conversation,
      account: account,
      inbox: inbox,
      status: :open,
      waiting_since: 2.hours.ago,
      assignee: agent
    )
    non_matching = create(
      :conversation,
      account: account,
      inbox: inbox,
      status: :open,
      waiting_since: 2.hours.ago,
      assignee_id: nil
    )
    # before_create initializes waiting_since from created_at, so set the episode timestamps explicitly.
    # rubocop:disable Rails/SkipsModelValidations
    matching.update_column(:waiting_since, 2.hours.ago)
    non_matching.update_column(:waiting_since, 2.hours.ago)
    # rubocop:enable Rails/SkipsModelValidations

    count = described_class.new(
      account: account,
      attributes: {
        trigger_type: 'agent_no_reply',
        duration_minutes: 60,
        conditions: [
          {
            'attribute_key' => 'assignee_id',
            'filter_operator' => 'equal_to',
            'values' => [agent.id],
            'query_operator' => 'AND'
          }
        ]
      }
    ).perform

    expect(count).to eq(1)
    expect(matching.assignee_id).to eq(agent.id)
  end
end
