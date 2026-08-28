require 'rails_helper'

RSpec.describe Custom::CustomRoles::NormalizeTimeFinanceiroService do
  let(:account) { create(:account) }

  it 'keeps non-scope permissions and sets team-unassigned as the conversation scope' do
    role = create(
      :custom_role,
      account: account,
      name: 'Time Financeiro',
      permissions: %w[
        conversation_unassigned_manage
        conversation_team_unassigned_manage
        conversation_participating_manage
        contact_manage
      ]
    )

    described_class.new(account_id: account.id).perform

    expect(role.reload.permissions).to contain_exactly('conversation_team_unassigned_manage', 'contact_manage')
  end
end
