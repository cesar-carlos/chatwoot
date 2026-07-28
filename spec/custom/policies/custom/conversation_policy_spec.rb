require 'rails_helper'

RSpec.describe ConversationPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent_account_user) { agent.account_users.find_by(account: account) }
  let(:context) { { user: agent, account: account, account_user: agent_account_user } }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  permissions :show? do
    context 'when custom role grants conversation_team_unassigned_manage' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_team_unassigned_manage']) }
      let(:agent_team) { create(:team, account: account) }
      let(:other_team) { create(:team, account: account) }

      before do
        agent_account_user.update!(role: :agent, custom_role: custom_role)
        create(:team_member, team: agent_team, user: agent)
      end

      it 'allows conversations assigned to the agent' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)

        expect(subject).to permit(context, conversation)
      end

      it 'allows unassigned conversations in the agent team with inbox access' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, team: agent_team)

        expect(subject).to permit(context, conversation)
      end

      it 'denies unassigned conversations in the agent team without inbox access' do
        other_inbox = create(:inbox, account: account)
        conversation = create(:conversation, account: account, inbox: other_inbox, assignee: nil, team: agent_team)

        expect(subject).not_to permit(context, conversation)
      end

      it 'denies unassigned conversations in another team' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, team: other_team)

        expect(subject).not_to permit(context, conversation)
      end

      it 'denies unassigned conversations without a team' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, team: nil)

        expect(subject).not_to permit(context, conversation)
      end
    end

    context 'when custom role grants conversation_manage without inbox access' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_manage']) }

      before do
        agent_account_user.update!(role: :agent, custom_role: custom_role)
      end

      it 'denies conversations in inaccessible inboxes' do
        other_inbox = create(:inbox, account: account)
        conversation = create(:conversation, account: account, inbox: other_inbox, assignee: nil)

        expect(subject).not_to permit(context, conversation)
      end
    end
  end
end
