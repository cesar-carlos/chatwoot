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

  context 'when migrating cross-channel (API ↔ WhatsApp archive)' do
    it 'remounts API to WhatsApp using phone-derived source_id' do
      api_inbox = create(:channel_api, account: account).inbox
      api_contact_inbox = create(
        :contact_inbox,
        inbox: api_inbox,
        contact: contact,
        source_id: 'api-session-uuid-xyz'
      )
      api_conversation = create(
        :conversation,
        account: account,
        inbox: api_inbox,
        contact: contact,
        contact_inbox: api_contact_inbox
      )
      create(:message, account: account, inbox: api_inbox, conversation: api_conversation)
      cross_migration = InboxHistoryMigration.create!(
        account: account,
        source_inbox: api_inbox,
        target_inbox: target_inbox,
        status: 'pending'
      )

      described_class.new(migration: cross_migration).perform

      expect(cross_migration.reload.status).to eq('completed')
      expect(cross_migration.stats['moved']).to eq(1)
      expect(api_conversation.reload.inbox_id).to eq(target_inbox.id)
      expect(api_conversation.contact_inbox.source_id).to eq('5511777666555')
      expect(api_conversation.contact_inbox.source_id).not_to eq('api-session-uuid-xyz')
    end

    it 'marks the peer failed when API to WhatsApp has no phone number' do
      api_inbox = create(:channel_api, account: account).inbox
      contact_without_phone = create(:contact, account: account, phone_number: nil)
      api_contact_inbox = create(
        :contact_inbox,
        inbox: api_inbox,
        contact: contact_without_phone,
        source_id: 'api-session-no-phone'
      )
      api_conversation = create(
        :conversation,
        account: account,
        inbox: api_inbox,
        contact: contact_without_phone,
        contact_inbox: api_contact_inbox
      )
      create(:message, account: account, inbox: api_inbox, conversation: api_conversation)
      cross_migration = InboxHistoryMigration.create!(
        account: account,
        source_inbox: api_inbox,
        target_inbox: target_inbox,
        status: 'pending'
      )

      described_class.new(migration: cross_migration).perform

      expect(cross_migration.reload.status).to eq('completed')
      expect(cross_migration.stats['failed']).to eq(1)
      expect(api_conversation.reload.inbox_id).to eq(api_inbox.id)
    end

    it 'remounts WhatsApp to API with a new UUID session' do
      api_inbox = create(:channel_api, account: account).inbox
      cross_migration = InboxHistoryMigration.create!(
        account: account,
        source_inbox: source_inbox,
        target_inbox: api_inbox,
        status: 'pending'
      )

      described_class.new(migration: cross_migration).perform

      expect(cross_migration.reload.status).to eq('completed')
      expect(cross_migration.stats['moved']).to eq(1)
      expect(conversation.reload.inbox_id).to eq(api_inbox.id)
      expect(conversation.contact_inbox.inbox_id).to eq(api_inbox.id)
      expect(conversation.contact_inbox.source_id).not_to eq('5511777666555')
      expect(conversation.contact_inbox.source_id).to be_present
    end

    it 'remounts Evolution group to API with a new UUID session' do
      evolution_inbox = create(
        :channel_whatsapp,
        account: account,
        provider: 'evolution',
        sync_templates: false,
        validate_provider_config: false
      ).inbox
      group_jid = '120363042343979999@g.us'
      group_contact = create(:contact, account: account, phone_number: nil, identifier: group_jid)
      group_contact_inbox = create(
        :contact_inbox,
        inbox: evolution_inbox,
        contact: group_contact,
        source_id: group_jid
      )
      group_conversation = create(
        :conversation,
        account: account,
        inbox: evolution_inbox,
        contact: group_contact,
        contact_inbox: group_contact_inbox
      )
      create(:message, account: account, inbox: evolution_inbox, conversation: group_conversation)
      api_inbox = create(:channel_api, account: account).inbox
      cross_migration = InboxHistoryMigration.create!(
        account: account,
        source_inbox: evolution_inbox,
        target_inbox: api_inbox,
        status: 'pending'
      )

      described_class.new(migration: cross_migration).perform

      expect(cross_migration.reload.status).to eq('completed')
      expect(cross_migration.stats['moved']).to eq(1)
      expect(group_conversation.reload.inbox_id).to eq(api_inbox.id)
      expect(group_conversation.contact_inbox.source_id).not_to eq(group_jid)
      expect(group_conversation.contact_inbox.source_id).to be_present
    end

    it 'reuses the same API contact_inbox on a second run (idempotent)' do
      api_inbox = create(:channel_api, account: account).inbox
      cross_migration = InboxHistoryMigration.create!(
        account: account,
        source_inbox: source_inbox,
        target_inbox: api_inbox,
        status: 'pending'
      )

      described_class.new(migration: cross_migration).perform
      first_ci_id = conversation.reload.contact_inbox_id
      first_source_id = conversation.contact_inbox.source_id

      # Simulate needing another remount of the same peer (e.g. partial ops recovery).
      conversation.update!(inbox_id: source_inbox.id, contact_inbox_id: source_contact_inbox.id)
      message.update!(inbox_id: source_inbox.id)

      rerun = InboxHistoryMigration.create!(
        account: account,
        source_inbox: source_inbox,
        target_inbox: api_inbox,
        status: 'pending'
      )
      described_class.new(migration: rerun).perform

      expect(rerun.reload.status).to eq('completed')
      expect(rerun.stats['moved']).to eq(1)
      expect(conversation.reload.contact_inbox_id).to eq(first_ci_id)
      expect(conversation.contact_inbox.source_id).to eq(first_source_id)
      expect(ContactInbox.where(inbox: api_inbox, contact: contact).count).to eq(1)
    end
  end

  it 'preserves WhatsApp source_id when the contact has no phone number' do
    contact_without_phone = create(:contact, account: account, phone_number: nil)
    source_ci = create(
      :contact_inbox,
      inbox: source_inbox,
      contact: contact_without_phone,
      source_id: '5511999888777'
    )
    conv = create(
      :conversation,
      account: account,
      inbox: source_inbox,
      contact: contact_without_phone,
      contact_inbox: source_ci
    )
    create(:message, account: account, inbox: source_inbox, conversation: conv)
    # Remove the default phone-backed conversation from this migration run.
    conversation.destroy!
    phone_migration = InboxHistoryMigration.create!(
      account: account,
      source_inbox: source_inbox,
      target_inbox: target_inbox,
      status: 'pending'
    )

    described_class.new(migration: phone_migration).perform

    expect(phone_migration.reload.status).to eq('completed')
    expect(phone_migration.stats['moved']).to eq(1)
    expect(conv.reload.inbox_id).to eq(target_inbox.id)
    expect(conv.contact_inbox.source_id).to eq('5511999888777')
  end

  it 'merges into a resolved destination conversation even when single-history lock is off' do
    target_inbox.update!(lock_to_single_conversation: false)
    target_contact_inbox = create(:contact_inbox, inbox: target_inbox, contact: contact, source_id: '5511777666555')
    target_conversation = create(
      :conversation,
      account: account,
      inbox: target_inbox,
      contact: contact,
      contact_inbox: target_contact_inbox,
      status: :resolved
    )
    create(:message, account: account, inbox: target_inbox, conversation: target_conversation, content: 'existing')

    described_class.new(migration: migration).perform

    expect(migration.reload.status).to eq('completed')
    expect(migration.stats['merged']).to eq(1)
    expect { conversation.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(target_conversation.reload.messages.count).to eq(2)
  end

  it 'does not steal source_id owned by another contact on the target' do
    other_contact = create(:contact, account: account, phone_number: '+5511000000099')
    create(:contact_inbox, inbox: target_inbox, contact: other_contact, source_id: '5511777666555')

    expect do
      described_class.new(migration: migration).perform
    end.not_to(change { ContactInbox.find_by(inbox: target_inbox, source_id: '5511777666555').contact_id })

    expect(migration.reload.stats['failed']).to eq(1)
    expect(ContactInbox.find_by(inbox: target_inbox, source_id: '5511777666555').contact_id).to eq(other_contact.id)
  end
end
