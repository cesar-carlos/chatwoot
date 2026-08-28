require 'rails_helper'

RSpec.describe InboxPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:agent_account_user) { agent.account_users.find_by(account: account) }
  let(:context) { { user: agent, account: account, account_user: agent_account_user } }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  permissions :update?, :manage_members?, :reset_secret? do
    context 'when custom role grants inbox_manage on an assigned inbox' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['inbox_manage']) }

      before { agent_account_user.update!(custom_role: custom_role) }

      it { expect(subject).to permit(context, inbox) }
      it { expect(subject).not_to permit(context, other_inbox) }
      it { expect(subject).not_to permit(context, Inbox) }
    end

    context 'when custom role lacks inbox_manage' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_participating_manage']) }

      before { agent_account_user.update!(custom_role: custom_role) }

      it { expect(subject).not_to permit(context, inbox) }
    end
  end

  permissions :create?, :destroy? do
    context 'when custom role grants inbox_manage' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['inbox_manage']) }

      before { agent_account_user.update!(custom_role: custom_role) }

      it { expect(subject).not_to permit(context, inbox) }
    end
  end
end
