# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Inboxes::HistoryMigration::ConversationMerger do
  let(:account) { create(:account) }
  let(:source_inbox) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
  end
  let(:target_inbox) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5511888777666') }
  let(:source_contact_inbox) do
    create(:contact_inbox, inbox: source_inbox, contact: contact, source_id: '5511888777666')
  end
  let(:target_contact_inbox) do
    create(:contact_inbox, inbox: target_inbox, contact: contact, source_id: '5511888777666')
  end
  let!(:source_conversation) do
    create(:conversation, account: account, inbox: source_inbox, contact: contact,
                          contact_inbox: source_contact_inbox, custom_attributes: { 'from_source' => true })
  end
  let!(:target_conversation) do
    create(:conversation, account: account, inbox: target_inbox, contact: contact,
                          contact_inbox: target_contact_inbox, custom_attributes: { 'from_target' => true })
  end
  let!(:source_message) do
    create(:message, account: account, inbox: source_inbox, conversation: source_conversation, content: 'from A')
  end
  let!(:target_message) do
    create(:message, account: account, inbox: target_inbox, conversation: target_conversation, content: 'from B')
  end

  before do
    source_conversation.update_labels('vip,urgent')
  end

  it 'merges messages into the target conversation and destroys the source' do
    described_class.new(
      source_conversation: source_conversation,
      target_conversation: target_conversation,
      target_inbox: target_inbox
    ).perform

    expect { source_conversation.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(target_conversation.reload.messages.pluck(:content)).to include('from A', 'from B')
    expect(source_message.reload.conversation_id).to eq(target_conversation.id)
    expect(source_message.inbox_id).to eq(target_inbox.id)
    expect(target_message.reload.conversation_id).to eq(target_conversation.id)
  end

  it 'merges labels and custom attributes preferring target values on conflict' do
    described_class.new(
      source_conversation: source_conversation,
      target_conversation: target_conversation,
      target_inbox: target_inbox
    ).perform

    target_conversation.reload
    expect(target_conversation.label_list).to include('vip', 'urgent')
    expect(target_conversation.custom_attributes['from_source']).to be(true)
    expect(target_conversation.custom_attributes['from_target']).to be(true)
  end

  it 'merges additional_attributes preferring target values on conflict' do
    source_conversation.update!(
      additional_attributes: { 'from_source' => true, 'shared' => 'source' }
    )
    target_conversation.update!(
      additional_attributes: { 'from_target' => true, 'shared' => 'target' }
    )

    described_class.new(
      source_conversation: source_conversation,
      target_conversation: target_conversation,
      target_inbox: target_inbox
    ).perform

    attrs = target_conversation.reload.additional_attributes
    expect(attrs['from_source']).to be(true)
    expect(attrs['from_target']).to be(true)
    expect(attrs['shared']).to eq('target')
  end

  it 'clears workflow rule executions so destroy does not hit FK' do
    skip 'ConversationWorkflowRuleExecution not loaded' unless defined?(ConversationWorkflowRuleExecution)

    rule = ConversationWorkflowRule.create!(
      account: account,
      name: 'Inactivity resolve',
      trigger_type: :conversation_inactivity,
      duration_minutes: 60,
      resolve_on_match: true,
      conditions: [],
      active: true
    )
    ConversationWorkflowRuleExecution.create!(
      conversation_workflow_rule: rule,
      conversation: source_conversation,
      executed_at: Time.current,
      last_activity_epoch: source_conversation.last_activity_at.to_i
    )

    expect do
      described_class.new(
        source_conversation: source_conversation,
        target_conversation: target_conversation,
        target_inbox: target_inbox
      ).perform
    end.not_to raise_error

    expect(ConversationWorkflowRuleExecution.where(conversation_id: source_conversation.id)).to be_empty
  end

  it 'reparents calls onto the target conversation' do
    skip 'Call model not loaded' unless defined?(Call)

    call = create(
      :call,
      conversation: source_conversation,
      account: account,
      inbox: source_inbox,
      contact: contact
    )

    described_class.new(
      source_conversation: source_conversation,
      target_conversation: target_conversation,
      target_inbox: target_inbox
    ).perform

    expect(call.reload.conversation_id).to eq(target_conversation.id)
    expect(call.inbox_id).to eq(target_inbox.id)
  end
end
