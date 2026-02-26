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
    context 'when role grants conversation_unassigned_manage' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_unassigned_manage']) }

      before do
        agent_account_user.update!(role: :agent, custom_role: custom_role)
      end

      it 'allows access to conversations assigned to the agent' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)

        expect(subject).to permit(context, conversation)
      end

      it 'denies access to conversations assigned to someone else' do
        other_agent = create(:user, account: account, role: :agent)
        conversation = create(:conversation, account: account, inbox: inbox, assignee: other_agent)

        expect(subject).not_to permit(context, conversation)
      end
    end

    context 'when role grants conversation_participating_manage' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_participating_manage']) }

      before do
        agent_account_user.update!(role: :agent, custom_role: custom_role)
      end

      it 'allows access to conversations assigned to the agent' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)

        expect(subject).to permit(context, conversation)
      end

      it 'allows access to conversations where the agent is a participant' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)
        create(:conversation_participant, conversation: conversation, account: account, user: agent)

        expect(subject).to permit(context, conversation)
      end

      it 'denies access to unrelated conversations' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        expect(subject).not_to permit(context, conversation)
      end
    end

    context 'when role grants conversation_team_unassigned_manage' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_team_unassigned_manage']) }
      let(:agent_team) { create(:team, account: account) }
      let(:other_team) { create(:team, account: account) }

      before do
        agent_account_user.update!(role: :agent, custom_role: custom_role)
        create(:team_member, team: agent_team, user: agent)
      end

      it 'allows access to conversations assigned to the agent' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)

        expect(subject).to permit(context, conversation)
      end

      it 'allows access to unassigned conversations in user team with inbox access' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, team: agent_team)

        expect(subject).to permit(context, conversation)
      end

      it 'denies access to unassigned conversations in user team without inbox access' do
        other_inbox = create(:inbox, account: account)
        conversation = create(:conversation, account: account, inbox: other_inbox, assignee: nil, team: agent_team)

        expect(subject).not_to permit(context, conversation)
      end

      it 'denies access to unassigned conversations in another team' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, team: other_team)

        expect(subject).not_to permit(context, conversation)
      end

      it 'denies access to unassigned conversations without team' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, team: nil)

        expect(subject).not_to permit(context, conversation)
      end
    end

    context 'when role grants conversation_manage but user does not have inbox access' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_manage']) }

      before do
        agent_account_user.update!(role: :agent, custom_role: custom_role)
      end

      it 'denies access to conversation in inaccessible inbox' do
        other_inbox = create(:inbox, account: account)
        conversation = create(:conversation, account: account, inbox: other_inbox, assignee: nil)

        expect(subject).not_to permit(context, conversation)
      end
    end
  end
end
