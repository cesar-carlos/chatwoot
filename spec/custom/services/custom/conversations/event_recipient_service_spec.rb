require 'rails_helper'

RSpec.describe Custom::Conversations::EventRecipientService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: other_agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:standard_agent) { create(:user, account: account, role: :agent) }
  let(:restricted_agent) { create(:user, account: account, role: :agent) }
  let(:participating_agent) { create(:user, account: account, role: :agent) }
  let(:contact_token) { conversation.contact_inbox.pubsub_token }

  before do
    [standard_agent, restricted_agent, participating_agent].each do |agent|
      create(:inbox_member, inbox: inbox, user: agent)
    end

    account.account_users.find_by!(user: restricted_agent).update!(
      custom_role: create(:custom_role, account: account, permissions: ['conversation_unassigned_manage'])
    )
    account.account_users.find_by!(user: participating_agent).update!(
      custom_role: create(:custom_role, account: account, permissions: ['conversation_participating_manage'])
    )
    create(:conversation_participant, account: account, conversation: conversation, user: participating_agent)
  end

  it 'keeps standard, administrator, participant and contact tokens while removing a denied custom-role agent' do
    tokens = [
      standard_agent.pubsub_token,
      admin.pubsub_token,
      restricted_agent.pubsub_token,
      participating_agent.pubsub_token,
      contact_token
    ]

    result = described_class.new(account: account, conversation: conversation, tokens: tokens).perform

    expect(result).to contain_exactly(
      standard_agent.pubsub_token,
      admin.pubsub_token,
      participating_agent.pubsub_token,
      contact_token
    )
  end

  it 'allows team-unassigned access only to members of the conversation team' do
    team = create(:team, account: account)
    team_member = create(:user, account: account, role: :agent)
    non_member = create(:user, account: account, role: :agent)
    [team_member, non_member].each do |agent|
      create(:inbox_member, inbox: inbox, user: agent)
      account.account_users.find_by!(user: agent).update!(
        custom_role: create(:custom_role, account: account, permissions: ['conversation_team_unassigned_manage'])
      )
    end
    create(:team_member, team: team, user: team_member)
    conversation.update!(assignee: nil, team: team)

    result = described_class.new(
      account: account,
      conversation: conversation,
      tokens: [team_member.pubsub_token, non_member.pubsub_token]
    ).perform

    expect(result).to eq([team_member.pubsub_token])
  end

  it 'does not treat an AgentBot assignment as unassigned' do
    agent_bot = create(:agent_bot, account: account)
    conversation.update!(assignee: nil, assignee_agent_bot: agent_bot)

    result = described_class.new(
      account: account,
      conversation: conversation,
      tokens: [restricted_agent.pubsub_token, participating_agent.pubsub_token]
    ).perform

    expect(result).to eq([participating_agent.pubsub_token])
  end
end
