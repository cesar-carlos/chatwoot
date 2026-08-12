# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Message::AgentOutgoingReopen do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :resolved,
      assignee: agent
    )
  end

  it 'reopens resolved conversation and stamps opened_by=agent' do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      private: false,
      sender: agent,
      content: 'bom dia'
    )

    expect(conversation.reload).to be_open
    expect(conversation.additional_attributes['opened_by']).to eq('agent')
  end

  it 'does not reopen for private notes' do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      private: true,
      sender: agent,
      content: 'nota interna'
    )

    expect(conversation.reload).to be_resolved
  end

  it 'keeps incoming reopen stamping opened_by=contact' do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      sender: contact,
      content: 'oi'
    )

    expect(conversation.reload).to be_open
    expect(conversation.additional_attributes['opened_by']).to eq('contact')
  end
end
