require 'rails_helper'

RSpec.describe Custom::CustomRoles::AuditScopeOverlapService do
  let(:account) { create(:account) }

  it 'reports roles with exclusive unassigned and team-unassigned scopes' do
    overlapping = create(
      :custom_role,
      account: account,
      name: 'Time Financeiro',
      permissions: %w[conversation_unassigned_manage conversation_team_unassigned_manage conversation_participating_manage]
    )
    create(:custom_role, account: account, permissions: ['conversation_team_unassigned_manage'])

    results = described_class.new(account_id: account.id).perform

    expect(results.map { |result| result.role.id }).to eq([overlapping.id])
    expect(results.first.effective).to eq('conversation_unassigned_manage')
    expect(results.first.overlapping).to eq(
      %w[conversation_unassigned_manage conversation_team_unassigned_manage]
    )
    expect(results.first.participating).to be(true)
  end

  it 'does not treat unassigned plus participating as overlap' do
    create(
      :custom_role,
      account: account,
      permissions: %w[conversation_unassigned_manage conversation_participating_manage]
    )

    expect(described_class.new(account_id: account.id).perform).to eq([])
  end

  it 'returns an empty list when no roles overlap' do
    create(:custom_role, account: account, permissions: ['conversation_participating_manage'])

    expect(described_class.new(account_id: account.id).perform).to eq([])
  end

  it 'skips roles that include conversation_manage' do
    create(
      :custom_role,
      account: account,
      permissions: %w[
        conversation_manage
        conversation_unassigned_manage
        conversation_team_unassigned_manage
      ]
    )

    expect(described_class.new(account_id: account.id).perform).to eq([])
  end
end
