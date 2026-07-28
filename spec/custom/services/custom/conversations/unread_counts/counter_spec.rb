require 'rails_helper'

RSpec.describe Conversations::UnreadCounts::Counter do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:label) { create(:label, account: account, title: 'support', show_on_sidebar: true) }
  let(:team) { create(:team, account: account, allow_auto_assign: false) }
  let(:account_user) { account.account_users.find_by(user: agent) }
  let(:store) { Conversations::UnreadCounts::Store }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    create(:team_member, user: agent, team: team)
  end

  after do
    store.clear_account!(account.id)
  end

  it 'counts mine and team-unassigned, including labeled team-unassigned via sinter' do
    other_team = create(:team, account: account, allow_auto_assign: false)
    account_user.update!(custom_role: create(:custom_role, account: account, permissions: ['conversation_team_unassigned_manage']))
    create_unread_conversation(account: account, inbox: inbox, labels: [label.title], assignee: agent, team: team)
    create_unread_conversation(account: account, inbox: inbox, labels: [label.title], team: team)
    create_unread_conversation(account: account, inbox: inbox, labels: [label.title], team: other_team)
    create_unread_conversation(account: account, inbox: inbox, labels: [label.title], team: nil)
    create_unread_conversation(account: account, inbox: inbox, labels: [label.title], assignee: other_agent, team: team)

    result = described_class.new(account: account, user: agent).perform

    expect(result[:all_count]).to eq(2)
    expect(result[:inboxes]).to eq(inbox.id.to_s => 2)
    expect(result[:labels]).to eq(label.id.to_s => 2)
    expect(result[:teams]).to eq(team.id.to_s => 2)
    expect(store.assignment_ready?(account.id)).to be(true)
  end

  it 'prefers conversation_unassigned_manage over conversation_team_unassigned_manage' do
    other_team = create(:team, account: account, allow_auto_assign: false)
    account_user.update!(
      custom_role: create(
        :custom_role,
        account: account,
        permissions: %w[conversation_team_unassigned_manage conversation_unassigned_manage]
      )
    )
    create_unread_conversation(account: account, inbox: inbox, assignee: agent, team: team)
    create_unread_conversation(account: account, inbox: inbox, team: team)
    create_unread_conversation(account: account, inbox: inbox, team: other_team)
    create_unread_conversation(account: account, inbox: inbox, team: nil)
    create_unread_conversation(account: account, inbox: inbox, assignee: other_agent, team: team)

    result = described_class.new(account: account, user: agent).perform

    expect(result[:all_count]).to eq(4)
    expect(result[:inboxes]).to eq(inbox.id.to_s => 4)
    expect(result[:teams]).to eq(team.id.to_s => 2)
    expect(store.assignment_ready?(account.id)).to be(true)
  end
end
