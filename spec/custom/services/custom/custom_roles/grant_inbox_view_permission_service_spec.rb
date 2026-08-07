require 'rails_helper'

RSpec.describe Custom::CustomRoles::GrantInboxViewPermissionService do
  let(:account) { create(:account) }

  it 'grants inbox_view_manage to roles with conversation permissions' do
    role = create(:custom_role, account: account, permissions: ['conversation_participating_manage'])

    expect(described_class.new.perform).to eq(1)
    expect(role.reload.permissions).to include('inbox_view_manage')
  end

  it 'does not grant to roles without conversation permissions' do
    role = create(:custom_role, account: account, permissions: ['contact_manage'])

    expect(described_class.new.perform).to eq(0)
    expect(role.reload.permissions).not_to include('inbox_view_manage')
  end

  it 'is idempotent when inbox_view_manage is already present' do
    role = create(
      :custom_role,
      account: account,
      permissions: %w[conversation_manage inbox_view_manage]
    )

    expect(described_class.new.perform).to eq(0)
    expect(role.reload.permissions.count('inbox_view_manage')).to eq(1)
  end
end
