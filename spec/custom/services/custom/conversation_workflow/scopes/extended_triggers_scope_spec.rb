require 'rails_helper'

# rubocop:disable RSpec/MultipleDescribes
RSpec.describe Custom::ConversationWorkflow::Scopes::UnassignedTooLongScope do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:rule) do
    create_workflow_rule!(
      account: account,
      name: 'Unassigned',
      trigger_type: :unassigned_too_long,
      active: true
    )
  end

  it 'includes open unassigned conversations past the cutoff' do
    matching = create(:conversation, account: account, inbox: inbox, assignee: nil, created_at: 2.hours.ago)
    create(:conversation, account: account, inbox: inbox, assignee: create(:user, account: account), created_at: 2.hours.ago)

    ids = described_class.new(account: account, rule: rule).perform.pluck(:id)
    expect(ids).to eq([matching.id])
  end
end

RSpec.describe Custom::ConversationWorkflow::Scopes::FirstResponseOverdueScope do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:rule) do
    create_workflow_rule!(
      account: account,
      name: 'Never attended',
      trigger_type: :first_response_overdue,
      active: true,
      duration_minutes: 30
    )
  end

  it 'includes conversations without first reply past waiting_since cutoff' do
    freeze_time do
      matching = create(
        :conversation,
        account: account,
        inbox: inbox,
        first_reply_created_at: nil,
        waiting_since: 1.hour.ago
      )
      # rubocop:disable Rails/SkipsModelValidations
      matching.update_column(:waiting_since, 1.hour.ago)
      # rubocop:enable Rails/SkipsModelValidations
      matching.reload
      create(
        :conversation,
        account: account,
        inbox: inbox,
        first_reply_created_at: Time.current,
        waiting_since: 1.hour.ago
      )

      ids = described_class.new(account: account, rule: rule).perform.pluck(:id)
      expect(ids).to eq([matching.id])
    end
  end
end
# rubocop:enable RSpec/MultipleDescribes
