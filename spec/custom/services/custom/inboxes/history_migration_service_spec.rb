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

  context 'when migrating API inboxes' do
    let(:source_inbox) { create(:channel_api, account: account).inbox }
    let(:target_inbox) { create(:channel_api, account: account).inbox }
    let(:contact) { create(:contact, account: account) }
    let(:session_id) { 'api-session-uuid-abc' }
    let(:source_contact_inbox) do
      create(:contact_inbox, inbox: source_inbox, contact: contact, source_id: session_id)
    end

    it 'preserves source_id when remounting' do
      described_class.new(migration: migration).perform

      expect(migration.reload.status).to eq('completed')
      expect(migration.stats['moved']).to eq(1)
      expect(conversation.reload.inbox_id).to eq(target_inbox.id)
      expect(conversation.contact_inbox.source_id).to eq(session_id)
      expect(conversation.contact_inbox.inbox_id).to eq(target_inbox.id)
    end

    it 'merges when destination already has the same source_id session' do
      target_contact_inbox = create(
        :contact_inbox,
        inbox: target_inbox,
        contact: contact,
        source_id: session_id
      )
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

    it 'marks the peer failed when source_id collides with another contact' do
      other_contact = create(:contact, account: account)
      create(:contact_inbox, inbox: target_inbox, contact: other_contact, source_id: session_id)

      described_class.new(migration: migration).perform

      expect(migration.reload.status).to eq('completed')
      expect(migration.stats['failed']).to eq(1)
      expect(conversation.reload.inbox_id).to eq(source_inbox.id)
    end
  end

  it 'marks conversations failed when WhatsApp source_id collides with another contact' do
    other_contact = create(:contact, account: account, phone_number: '+5511000000001')
    create(:contact_inbox, inbox: target_inbox, contact: other_contact, source_id: '5511777666555')

    described_class.new(migration: migration).perform

    expect(migration.reload.status).to eq('completed')
    expect(migration.stats['failed']).to eq(1)
    expect(conversation.reload.inbox_id).to eq(source_inbox.id)
    # Builder must not steal the other contact's identity on the target inbox.
    expect(ContactInbox.find_by(inbox: target_inbox, source_id: '5511777666555').contact_id).to eq(other_contact.id)
  end
end
