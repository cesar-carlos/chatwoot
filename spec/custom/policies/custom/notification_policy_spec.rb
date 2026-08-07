require 'rails_helper'

RSpec.describe NotificationPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:agent_account_user) { agent.account_users.find_by(account: account) }
  let(:context) { { user: agent, account: account, account_user: agent_account_user } }

  permissions :access? do
    it 'allows agents without a custom role' do
      expect(subject).to permit(context, Notification)
    end

    it 'allows administrators' do
      admin = create(:user, account: account, role: :administrator)
      admin_context = {
        user: admin,
        account: account,
        account_user: admin.account_users.find_by(account: account)
      }

      expect(subject).to permit(admin_context, Notification)
    end

    context 'when custom role grants inbox_view_manage' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['inbox_view_manage']) }

      before { agent_account_user.update!(role: :agent, custom_role: custom_role) }

      it 'allows access' do
        expect(subject).to permit(context, Notification)
      end
    end

    context 'when custom role lacks inbox_view_manage' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_participating_manage']) }

      before { agent_account_user.update!(role: :agent, custom_role: custom_role) }

      it 'denies access' do
        expect(subject).not_to permit(context, Notification)
      end
    end
  end
end
