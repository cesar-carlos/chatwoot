# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Inboxes::HistoryMigrationService do
  let(:account) { create(:account) }
  let(:source_inbox) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
  end
  let(:target_inbox) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5511777666555') }
  let(:source_contact_inbox) do
    create(:contact_inbox, inbox: source_inbox, contact: contact, source_id: '5511777666555')
  end
  let!(:conversation) do
    create(:conversation, account: account, inbox: source_inbox, contact: contact, contact_inbox: source_contact_inbox)
  end
  let!(:message) do
    create(:message, account: account, inbox: source_inbox, conversation: conversation)
  end
  let(:migration) do
    InboxHistoryMigration.create!(
      account: account,
      source_inbox: source_inbox,
      target_inbox: target_inbox,
      status: 'pending'
    )
  end

  it 'moves conversations when the destination has no existing conversation' do
    described_class.new(migration: migration).perform

    expect(migration.reload.status).to eq('completed')
    expect(migration.stats['moved']).to eq(1)
    expect(conversation.reload.inbox_id).to eq(target_inbox.id)
    expect(message.reload.inbox_id).to eq(target_inbox.id)
  end

  it 'merges when the destination already has a conversation for the contact' do
    target_contact_inbox = create(:contact_inbox, inbox: target_inbox, contact: contact, source_id: '5511777666555')
    target_conversation = create(
      :conversation,
      account: account,
      inbox: target_inbox,
      contact: contact,
      contact_inbox: target_contact_inbox
    )
    create(:message, account: account, inbox: target_inbox, conversation: target_conversation, content: 'existing')

    described_class.new(migration: migration).perform

    expect(migration.reload.status).to eq('completed')
    expect(migration.stats['merged']).to eq(1)
    expect { conversation.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(target_conversation.reload.messages.count).to eq(2)
  end
end
