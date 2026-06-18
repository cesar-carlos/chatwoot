require 'rails_helper'

RSpec.describe Conversations::Resolver do
  subject(:resolver_call) do
    described_class.new(
      inbox: inbox,
      contact_inbox: contact_inbox,
      conversation_params: conversation_params
    ).perform
  end

  let(:account) { create(:account) }
  let(:lock_to_single_conversation) { false }
  let(:inbox) { create(:inbox, account: account, lock_to_single_conversation: lock_to_single_conversation) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation_params) do
    {
      account_id: account.id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id
    }
  end

  it 'wraps lookup/create in a contact_inbox lock' do
    allow(contact_inbox).to receive(:with_lock).and_yield

    resolver_call

    expect(contact_inbox).to have_received(:with_lock).once
  end

  describe '#resolve_or_create' do
    subject(:resolve_or_create) do
      described_class.new(inbox: inbox, contact_inbox: contact_inbox).resolve_or_create { conversation_params }
    end

    it 'uses a single lock for find-or-create' do
      allow(contact_inbox).to receive(:with_lock).and_yield

      resolve_or_create

      expect(contact_inbox).to have_received(:with_lock).once
    end

    it 'does not evaluate create params when a conversation exists' do
      existing = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :open)

      expect { resolve_or_create }.not_to change(Conversation, :count)
      expect(resolve_or_create).to eq(existing)
    end
  end

  context 'when lock_to_single_conversation is enabled' do
    let(:inbox) { create(:inbox, :single_history, account: account) }

    it 'reuses latest conversation even if resolved' do
      older = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)
      latest = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)

      expect(resolver_call).to eq(latest)
      expect(resolver_call).not_to eq(older)
    end
  end

  context 'when lock_to_single_conversation is disabled' do
    let(:lock_to_single_conversation) { false }

    it 'reuses latest non-resolved conversation' do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)
      latest_open = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :open)

      expect(resolver_call).to eq(latest_open)
    end

    it 'creates a new conversation when only resolved conversations exist' do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)

      expect { resolver_call }.to change(Conversation, :count).by(1)
      expect(resolver_call).to be_open
    end

    it 'find returns nil when only resolved conversations exist' do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)

      found = described_class.new(
        inbox: inbox,
        contact_inbox: contact_inbox,
        conversation_params: conversation_params
      ).find

      expect(found).to be_nil
    end
  end
end
