# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Conversations API agent start', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, lock_to_single_conversation: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  it 'returns 422 with a clear message when open conversation is assigned to another agent' do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :open,
      assignee: other_agent
    )

    post "/api/v1/accounts/#{account.id}/conversations",
         headers: agent.create_new_auth_token,
         params: {
           inbox_id: inbox.id,
           contact_id: contact.id,
           source_id: contact_inbox.source_id,
           message: { content: 'bom dia' }
         },
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['message']).to eq(
      I18n.t('errors.conversations.open_assigned_to_other_agent')
    )
  end

  it 'reopens a resolved conversation, assigns the agent, and accepts the message' do
    existing = create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :resolved,
      assignee: other_agent
    )

    post "/api/v1/accounts/#{account.id}/conversations",
         headers: agent.create_new_auth_token,
         params: {
           inbox_id: inbox.id,
           contact_id: contact.id,
           source_id: contact_inbox.source_id,
           message: { content: 'bom dia' }
         },
         as: :json

    expect(response).to have_http_status(:success)
    expect(existing.reload).to be_open
    expect(existing.assignee_id).to eq(agent.id)
    expect(existing.messages.outgoing.last.content).to eq('bom dia')
  end

  it 'returns 422 when open unassigned conversation is outside the agent permission scope' do
    agent_team = create(:team, account: account)
    other_team = create(:team, account: account)
    create(:team_member, team: agent_team, user: agent)
    custom_role = create(:custom_role, account: account, permissions: %w[conversation_team_unassigned_manage])
    AccountUser.find_by(user: agent, account: account).update!(custom_role: custom_role)

    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :open,
      assignee: nil,
      team: other_team
    )

    post "/api/v1/accounts/#{account.id}/conversations",
         headers: agent.create_new_auth_token,
         params: {
           inbox_id: inbox.id,
           contact_id: contact.id,
           source_id: contact_inbox.source_id,
           message: { content: 'bom dia' }
         },
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['message']).to eq(
      I18n.t('errors.conversations.outside_permission_scope')
    )
  end
end
