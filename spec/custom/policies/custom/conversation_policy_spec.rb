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
    context 'when custom role grants conversation_unassigned_manage' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_unassigned_manage']) }

      before do
        agent_account_user.update!(role: :agent, custom_role: custom_role)
      end

      it 'denies conversations assigned to an agent bot' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee_agent_bot: create(:agent_bot, account: account))

        expect(subject).not_to permit(context, conversation)
      end
    end

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

      it 'denies conversations assigned to an agent bot' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee_agent_bot: create(:agent_bot, account: account),
                                             team: agent_team)

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

  permissions :reply? do
    context 'when agent has no custom role' do
      it 'allows reply on unassigned conversation' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        expect(subject).to permit(context, conversation)
      end
    end

    context 'when custom role does not include conversation_reply_assigned_only' do
      let(:custom_role) do
        create(:custom_role, account: account, permissions: ['conversation_team_unassigned_manage'])
      end

      before do
        agent_account_user.update!(role: :agent, custom_role: custom_role)
      end

      it 'allows reply on unassigned conversation' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        expect(subject).to permit(context, conversation)
      end
    end

    context 'when custom role includes conversation_reply_assigned_only' do
      let(:custom_role) do
        create(
          :custom_role,
          account: account,
          permissions: %w[conversation_team_unassigned_manage conversation_reply_assigned_only]
        )
      end
      let(:other_agent) { create(:user, account: account, role: :agent) }

      before do
        agent_account_user.update!(role: :agent, custom_role: custom_role)
      end

      it 'allows reply when conversation is assigned to the agent' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)

        expect(subject).to permit(context, conversation)
      end

      it 'denies reply when conversation is unassigned' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        expect(subject).not_to permit(context, conversation)
      end

      it 'denies reply when conversation is assigned to another agent' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: other_agent)

        expect(subject).not_to permit(context, conversation)
      end
    end

    context 'when user is an administrator' do
      let(:admin) { create(:user, account: account, role: :administrator) }
      let(:admin_account_user) { admin.account_users.find_by(account: account) }
      let(:admin_context) { { user: admin, account: account, account_user: admin_account_user } }

      it 'allows reply on unassigned conversation' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        expect(subject).to permit(admin_context, conversation)
      end
    end
  end
end
