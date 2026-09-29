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
    expect do
      described_class.new(
        source_conversation: source_conversation,
        target_conversation: target_conversation,
        target_inbox: target_inbox
      ).perform
    end.to have_enqueued_job(Conversations::ActivityMessageJob)

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

  it 'preserves Enterprise and Captain records on the target conversation' do
    assistant = create(:captain_assistant, account: account)
    create(
      :conversation_outcome,
      account: account,
      assistant: assistant,
      inbox: target_inbox,
      conversation: target_conversation,
      started_at: 2.hours.ago
    )
    source_outcome = create(
      :conversation_outcome,
      account: account,
      assistant: assistant,
      inbox: source_inbox,
      conversation: source_conversation,
      started_at: 1.hour.ago
    )
    response = create(
      :captain_assistant_response,
      account: account,
      assistant: assistant,
      documentable: source_conversation
    )
    observation = Captain::FaqObservation.create!(
      account: account,
      conversation: source_conversation,
      generated_question: 'How do I migrate?',
      generated_answer: 'Use the history migration.',
      language: 'en',
      status: :discarded
    )
    report = create(
      :captain_message_report,
      message: source_message,
      user: create(:user, account: account)
    )

    described_class.new(
      source_conversation: source_conversation,
      target_conversation: target_conversation,
      target_inbox: target_inbox
    ).perform

    expect(source_outcome.reload).to have_attributes(
      conversation_id: target_conversation.id,
      inbox_id: target_inbox.id,
      episode_trigger: 'reopen'
    )
    expect(source_outcome.ended_at).to be_present
    expect(response.reload.documentable).to eq(target_conversation)
    expect(observation.reload.conversation_id).to eq(target_conversation.id)
    expect(report.reload.conversation_id).to eq(target_conversation.id)
  end

  it 'keeps one applied SLA and remounts historical events when policies differ' do
    source_policy = create(:sla_policy, account: account, name: 'Source SLA')
    target_policy = create(:sla_policy, account: account, name: 'Target SLA')
    source_conversation.update!(sla_policy_id: source_policy.id)
    target_conversation.update!(sla_policy_id: target_policy.id)
    source_applied_sla = AppliedSla.find_by!(conversation: source_conversation)
    target_applied_sla = AppliedSla.find_by!(conversation: target_conversation)
    source_event = create(
      :sla_event,
      applied_sla: source_applied_sla,
      conversation: source_conversation,
      inbox: source_inbox,
      sla_policy: source_policy
    )

    described_class.new(
      source_conversation: source_conversation,
      target_conversation: target_conversation,
      target_inbox: target_inbox
    ).perform

    expect(AppliedSla.where(conversation: target_conversation)).to contain_exactly(target_applied_sla)
    expect(AppliedSla.exists?(source_applied_sla.id)).to be(false)
    expect(source_event.reload).to have_attributes(
      applied_sla_id: target_applied_sla.id,
      conversation_id: target_conversation.id,
      inbox_id: target_inbox.id,
      sla_policy_id: source_policy.id
    )
  end

  it 'does not enqueue post-commit work when the outer transaction rolls back' do
    expect(Conversations::UnreadCounts::Refresher).not_to receive(:new)
    expect do
      ActiveRecord::Base.transaction(requires_new: true) do
        described_class.new(
          source_conversation: source_conversation,
          target_conversation: target_conversation,
          target_inbox: target_inbox
        ).perform
        raise ActiveRecord::Rollback
      end
    end.not_to have_enqueued_job(Conversations::ActivityMessageJob)

    expect(source_conversation.reload).to be_present
  end
end
