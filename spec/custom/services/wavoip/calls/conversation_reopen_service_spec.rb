# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::ConversationReopenService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
  end

  def conversation_with(status:)
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: status
    )
  end

  it 'reopens resolved conversations as open when requested' do
    conversation = conversation_with(status: :resolved)

    described_class.perform!(conversation: conversation, status: :open)

    expect(conversation.reload).to be_open
  end

  it 'reopens resolved conversations as pending for inbound calls' do
    conversation = conversation_with(status: :resolved)

    described_class.perform!(conversation: conversation, status: :pending)

    expect(conversation.reload).to be_pending
  end

  it 'reopens open conversations as pending for inbound calls' do
    conversation = conversation_with(status: :open)

    described_class.perform!(conversation: conversation, status: :pending)

    expect(conversation.reload).to be_pending
  end

  it 'reopens snoozed conversations' do
    conversation = conversation_with(status: :snoozed)

    described_class.perform!(conversation: conversation, status: :open)

    expect(conversation.reload).to be_open
  end

  it 'reopens pending conversations to open for outbound calls' do
    conversation = conversation_with(status: :pending)

    described_class.perform!(conversation: conversation, status: :open)

    expect(conversation.reload).to be_open
  end

  it 'no-ops for already open conversations' do
    conversation = conversation_with(status: :open)

    expect { described_class.perform!(conversation: conversation) }
      .not_to(change { conversation.reload.status })
  end

  it 'no-ops for non-wavoip inboxes' do
    whatsapp_channel = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
    conversation = create(
      :conversation,
      account: account,
      inbox: whatsapp_channel.inbox,
      contact: contact,
      status: :resolved
    )

    described_class.perform!(conversation: conversation)

    expect(conversation.reload).to be_resolved
  end
end
