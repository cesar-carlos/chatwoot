# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Conversations::AgentStartService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, lock_to_single_conversation: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:params) { ActionController::Parameters.new({}) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    Current.conversation_opened_by = Custom::Conversations::OpenedByStamper::AGENT
  end

  after { Current.reset }

  def perform_service
    described_class.new(contact_inbox: contact_inbox, user: agent, params: params).perform
  end

  it 'creates a conversation assigned to the initiating agent' do
    conversation = perform_service

    expect(conversation).to be_persisted
    expect(conversation.assignee_id).to eq(agent.id)
    expect(conversation).to be_open
    expect(conversation.additional_attributes['opened_by']).to eq('agent')
  end

  it 'reopens a resolved conversation and assigns the initiating agent' do
    existing = create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :resolved,
      assignee: other_agent
    )

    conversation = perform_service

    expect(conversation.id).to eq(existing.id)
    expect(conversation.reload).to be_open
    expect(conversation.assignee_id).to eq(agent.id)
    expect(conversation.additional_attributes['opened_by']).to eq('agent')
  end

  it 'reopens a snoozed conversation and assigns the initiating agent' do
    existing = create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :snoozed,
      assignee: other_agent
    )

    conversation = perform_service

    expect(conversation.id).to eq(existing.id)
    expect(conversation.reload).to be_open
    expect(conversation.assignee_id).to eq(agent.id)
  end

  it 'raises when conversation is open and assigned to another agent' do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :open,
      assignee: other_agent
    )

    expect { perform_service }.to raise_error(CustomExceptions::Conversation::OpenAssignedToOtherAgent)
  end

  it 'assigns an open unassigned conversation to the initiating agent' do
    existing = create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :open,
      assignee: nil
    )

    conversation = perform_service

    expect(conversation.id).to eq(existing.id)
    expect(conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'reuses an open conversation already assigned to the initiating agent' do
    existing = create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :open,
      assignee: agent
    )

    conversation = perform_service

    expect(conversation.id).to eq(existing.id)
    expect(conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'opens a pending conversation and stamps opened_by=agent' do
    existing = create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :pending,
      assignee: nil,
      additional_attributes: { 'opened_by' => 'contact' }
    )

    conversation = perform_service

    expect(conversation.id).to eq(existing.id)
    expect(conversation.reload).to be_open
    expect(conversation.assignee_id).to eq(agent.id)
    expect(conversation.additional_attributes['opened_by']).to eq('agent')
  end

  context 'with conversation_team_unassigned_manage custom role' do
    let(:agent_team) { create(:team, account: account) }
    let(:other_team) { create(:team, account: account) }

    before do
      create(:team_member, team: agent_team, user: agent)
      custom_role = create(:custom_role, account: account, permissions: %w[conversation_team_unassigned_manage])
      AccountUser.find_by(user: agent, account: account).update!(custom_role: custom_role)
    end

    it 'assigns unassigned conversation on the agent team' do
      existing = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :open,
        assignee: nil,
        team: agent_team
      )

      conversation = perform_service

      expect(conversation.id).to eq(existing.id)
      expect(conversation.reload.assignee_id).to eq(agent.id)
    end

    it 'raises OutsidePermissionScope for unassigned conversation on another team' do
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

      expect { perform_service }.to raise_error(CustomExceptions::Conversation::OutsidePermissionScope)
    end
  end

  context 'when inbox is Wavoip with lock_to_single_conversation false' do
    let(:channel) { create(:channel_wavoip, account: account) }
    let(:inbox) { channel.inbox.tap { |i| i.update!(lock_to_single_conversation: false) } }

    it 'reuses the latest resolved conversation instead of creating a new one' do
      existing = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :resolved,
        assignee: other_agent
      )

      conversation = perform_service

      expect(conversation.id).to eq(existing.id)
      expect(conversation.reload).to be_open
      expect(conversation.assignee_id).to eq(agent.id)
    end
  end

  context 'when lock_to_single_conversation is false on a non-Wavoip inbox' do
    let(:inbox) { create(:inbox, account: account, lock_to_single_conversation: false) }

    it 'creates a new conversation when only a resolved one exists' do
      create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :resolved,
        assignee: other_agent
      )

      expect { perform_service }.to change(Conversation, :count).by(1)
      expect(Conversation.order(:id).last.assignee_id).to eq(agent.id)
    end
  end
end
