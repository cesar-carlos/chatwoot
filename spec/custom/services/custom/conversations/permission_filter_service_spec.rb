require 'rails_helper'

RSpec.describe Conversations::PermissionFilterService do
  describe 'custom role conversation_team_unassigned_manage' do
    it 'returns mine and unassigned conversations from the agent teams only' do
      test_account = create(:account)
      test_inbox = create(:inbox, account: test_account)
      test_inbox2 = create(:inbox, account: test_account)
      test_agent = create(:user, account: test_account, role: :agent)
      create(:inbox_member, user: test_agent, inbox: test_inbox)

      agent_team = create(:team, account: test_account)
      other_team = create(:team, account: test_account)
      create(:team_member, team: agent_team, user: test_agent)

      test_custom_role = create(:custom_role, account: test_account, permissions: %w[conversation_team_unassigned_manage])
      account_user = AccountUser.find_by(user: test_agent, account: test_account)
      account_user.update(role: :agent, custom_role: test_custom_role)

      assigned_to_agent = create(:conversation, account: test_account, inbox: test_inbox, assignee: test_agent)
      team_unassigned = create(:conversation, account: test_account, inbox: test_inbox, assignee: nil, team: agent_team)
      other_team_unassigned = create(:conversation, account: test_account, inbox: test_inbox, assignee: nil, team: other_team)
      no_team_unassigned = create(:conversation, account: test_account, inbox: test_inbox, assignee: nil, team: nil)
      other_assigned = create(:conversation, account: test_account, inbox: test_inbox, assignee: create(:user, account: test_account))
      inaccessible_inbox_team_unassigned = create(
        :conversation,
        account: test_account,
        inbox: test_inbox2,
        assignee: nil,
        team: agent_team
      )

      result = described_class.new(
        test_account.conversations,
        test_agent,
        test_account
      ).perform

      expect(result).to include(assigned_to_agent)
      expect(result).to include(team_unassigned)
      expect(result).not_to include(other_team_unassigned)
      expect(result).not_to include(no_team_unassigned)
      expect(result).not_to include(other_assigned)
      expect(result).not_to include(inaccessible_inbox_team_unassigned)
    end

    it 'prefers conversation_unassigned_manage when both permissions are present' do
      test_account = create(:account)
      test_inbox = create(:inbox, account: test_account)
      test_agent = create(:user, account: test_account, role: :agent)
      create(:inbox_member, user: test_agent, inbox: test_inbox)

      agent_team = create(:team, account: test_account)
      other_team = create(:team, account: test_account)
      create(:team_member, team: agent_team, user: test_agent)

      test_custom_role = create(
        :custom_role,
        account: test_account,
        permissions: %w[conversation_team_unassigned_manage conversation_unassigned_manage]
      )
      account_user = AccountUser.find_by(user: test_agent, account: test_account)
      account_user.update(role: :agent, custom_role: test_custom_role)

      assigned_to_agent = create(:conversation, account: test_account, inbox: test_inbox, assignee: test_agent)
      team_unassigned = create(:conversation, account: test_account, inbox: test_inbox, assignee: nil, team: agent_team)
      other_team_unassigned = create(:conversation, account: test_account, inbox: test_inbox, assignee: nil, team: other_team)
      no_team_unassigned = create(:conversation, account: test_account, inbox: test_inbox, assignee: nil, team: nil)

      result = described_class.new(
        test_account.conversations,
        test_agent,
        test_account
      ).perform

      expect(result).to include(assigned_to_agent)
      expect(result).to include(team_unassigned)
      expect(result).to include(other_team_unassigned)
      expect(result).to include(no_team_unassigned)
    end

    it 'includes participating conversations when participating is combined with unassigned' do
      test_account = create(:account)
      test_inbox = create(:inbox, account: test_account)
      test_agent = create(:user, account: test_account, role: :agent)
      other_agent = create(:user, account: test_account, role: :agent)
      create(:inbox_member, user: test_agent, inbox: test_inbox)

      test_custom_role = create(
        :custom_role,
        account: test_account,
        permissions: %w[conversation_unassigned_manage conversation_participating_manage]
      )
      account_user = AccountUser.find_by(user: test_agent, account: test_account)
      account_user.update(role: :agent, custom_role: test_custom_role)

      participating = create(:conversation, account: test_account, inbox: test_inbox, assignee: other_agent)
      create(:conversation_participant, conversation: participating, user: test_agent, account: test_account)
      other_assigned = create(:conversation, account: test_account, inbox: test_inbox, assignee: other_agent)

      result = described_class.new(
        test_account.conversations,
        test_agent,
        test_account
      ).perform

      expect(result).to include(participating)
      expect(result).not_to include(other_assigned)
    end

    it 'includes participating conversations when participating is combined with team unassigned' do
      test_account = create(:account)
      test_inbox = create(:inbox, account: test_account)
      test_agent = create(:user, account: test_account, role: :agent)
      other_agent = create(:user, account: test_account, role: :agent)
      create(:inbox_member, user: test_agent, inbox: test_inbox)

      agent_team = create(:team, account: test_account)
      create(:team_member, team: agent_team, user: test_agent)

      test_custom_role = create(
        :custom_role,
        account: test_account,
        permissions: %w[conversation_team_unassigned_manage conversation_participating_manage]
      )
      account_user = AccountUser.find_by(user: test_agent, account: test_account)
      account_user.update(role: :agent, custom_role: test_custom_role)

      participating = create(:conversation, account: test_account, inbox: test_inbox, assignee: other_agent)
      create(:conversation_participant, conversation: participating, user: test_agent, account: test_account)
      other_assigned = create(:conversation, account: test_account, inbox: test_inbox, assignee: other_agent)

      result = described_class.new(
        test_account.conversations,
        test_agent,
        test_account
      ).perform

      expect(result).to include(participating)
      expect(result).not_to include(other_assigned)
    end
  end
end
