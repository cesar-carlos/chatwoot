# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Inboxes::HistoryMigration::Remounter do
  let(:account) { create(:account) }
  let(:source_inbox) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
  end
  let(:target_inbox) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:source_contact_inbox) do
    create(:contact_inbox, inbox: source_inbox, contact: contact, source_id: '5511999999999')
  end
  let(:target_contact_inbox) do
    create(:contact_inbox, inbox: target_inbox, contact: contact, source_id: '5511999999999')
  end
  let!(:conversation) do
    create(:conversation, account: account, inbox: source_inbox, contact: contact, contact_inbox: source_contact_inbox)
  end
  let!(:message) do
    create(:message, account: account, inbox: source_inbox, conversation: conversation, content: 'hello')
  end

  it 'moves conversation and messages to the target inbox' do
    described_class.new(
      conversation: conversation,
      target_inbox: target_inbox,
      target_contact_inbox: target_contact_inbox,
      source_inbox: source_inbox
    ).perform

    expect(conversation.reload.inbox_id).to eq(target_inbox.id)
    expect(conversation.contact_inbox_id).to eq(target_contact_inbox.id)
    expect(message.reload.inbox_id).to eq(target_inbox.id)
  end

  it 'clears assignee when the agent is not a member of the target inbox' do
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agent, inbox: source_inbox)
    conversation.update!(assignee: agent)

    described_class.new(
      conversation: conversation,
      target_inbox: target_inbox,
      target_contact_inbox: target_contact_inbox,
      source_inbox: source_inbox
    ).perform

    expect(conversation.reload.assignee_id).to be_nil
  end
end
