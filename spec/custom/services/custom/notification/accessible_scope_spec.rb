require 'rails_helper'

RSpec.describe Custom::Notification::AccessibleScope do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account, allow_auto_assign: false) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team) }
  let!(:notification) { create(:notification, account: account, user: user, primary_actor: conversation) }
  let(:scope) { described_class.for(user: user, account: account) }

  before { team.members << user }

  it 'uses one authorization scope for history and both counters after team access is lost' do
    expect(scope).to include(notification)
    team.team_members.where(user: user).destroy_all
    finder = NotificationFinder.new(user, account, includes: ['read'])
    expect(finder.notifications).to be_empty
    expect(finder.count).to eq(0)
    expect(finder.unread_count).to eq(0)
    expect(notification.reload).to be_persisted
  end

  it 'preserves authorized history even after the event itself is no longer eligible for delivery' do
    create(:inbox_member, user: user, inbox: inbox)
    conversation.update!(assignee: user)
    team.team_members.where(user: user).destroy_all
    expect(scope).to include(notification)
  end

  it 'returns no records or counts after account membership is removed' do
    user.account_users.find_by!(account: account).destroy!
    expect(scope).to be_empty
    expect(NotificationFinder.new(user, account).unread_count).to eq(0)
  end

  it 'does not expose notifications after the account is suspended, even with a cached account instance' do
    Account.find(account.id).update!(status: :suspended)
    expect(scope).to be_empty
  end

  it 'scopes even administrator history to existing conversations in the same account' do
    user.account_users.find_by!(account: account).update!(role: :administrator)
    expect(scope).to include(notification)
    other = create(:conversation)
    invalid = create(:notification, user: user, account: account, primary_actor: other)
    expect(scope).not_to include(invalid)
  end

  it 'does not bypass ConversationPolicy restrictions for an administrator carrying a custom role' do
    role = create(:custom_role, account: account, permissions: ['conversation_participating_manage'])
    account_user = user.account_users.find_by!(account: account)
    account_user.update!(role: :administrator, custom_role: role)
    context = { user: user, account: account, account_user: account_user }
    expect(ConversationPolicy.new(context, conversation).show?).to be(false)
    expect(scope).to be_empty
    create(:inbox_member, user: user, inbox: inbox)
    create(:conversation_participant, user: user, account: account, conversation: conversation)
    expect(ConversationPolicy.new(context, conversation).show?).to be(true)
    expect(scope).to include(notification)
  end

  notification_permissions = ['inbox_view_manage']
  [[], ['conversation_manage'], ['conversation_unassigned_manage'], ['conversation_team_unassigned_manage'],
   ['conversation_participating_manage'], %w[conversation_team_unassigned_manage conversation_participating_manage]].each do |permissions|
    it "matches ConversationPolicy for role permissions #{permissions.inspect}" do
      role = create(:custom_role, account: account, permissions: notification_permissions + permissions)
      account_user = user.account_users.find_by!(account: account)
      account_user.update!(custom_role: role)
      create(:inbox_member, user: user, inbox: inbox)
      other_team = create(:team, account: account, allow_auto_assign: false)
      bot = create(:agent_bot)
      conversations = [conversation,
                       create(:conversation, account: account, inbox: inbox, team: other_team),
                       create(:conversation, account: account, inbox: inbox, assignee: user),
                       create(:conversation, account: account, inbox: inbox, ai_assignee: bot),
                       create(:conversation, account: account)]
      create(:conversation_participant, user: user, conversation: conversations[1], account: account)
      rows = conversations.map { |actor| create(:notification, user: user, account: account, primary_actor: actor) }
      context = { user: user, account: account, account_user: account_user }
      expected = rows.select { |row| ConversationPolicy.new(context, row.conversation).show? }.map(&:id)
      expect(scope.where(id: rows.map(&:id)).pluck(:id)).to match_array(expected)
    end
  end

  it 'returns no history when the role lacks notification access despite conversation access' do
    role = create(:custom_role, account: account, permissions: ['conversation_manage'])
    user.account_users.find_by!(account: account).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: inbox)
    expect(scope).to be_empty
  end
end
