require 'rails_helper'

RSpec.describe Custom::ConversationWorkflow::SendMessageToContactService do
  let(:account) { create(:account) }
  let(:rule) do
    ConversationWorkflowRule.create!(
      account: account,
      name: 'Send contact',
      trigger_type: :customer_no_reply,
      duration_minutes: 15,
      actions: [{
        'action_name' => 'send_message_to_contact',
        'action_params' => [1, 2, 'Hello {{contact.name}}']
      }]
    )
  end
  let(:conversation) { create(:conversation, account: account) }

  it 'records a skip when the message template interpolates blank' do
    described_class.new(
      account: account,
      rule: rule,
      conversation: conversation,
      inbox_id: 1,
      contact_id: 2,
      message_template: '   '
    ).perform

    skip = ConversationWorkflowRuleSkip.last
    expect(skip).to be_present
    expect(skip.reason).to eq('blank_message')
    expect(skip.action_name).to eq('send_message_to_contact')
  end

  it 'records a skip when inbox or contact is missing' do
    described_class.new(
      account: account,
      rule: rule,
      conversation: conversation,
      inbox_id: 999_999,
      contact_id: 999_999,
      message_template: 'Hello'
    ).perform

    skip = ConversationWorkflowRuleSkip.last
    expect(skip.reason).to eq('missing_inbox_or_contact')
  end

  it 'interpolates liquid from the trigger conversation and rule' do
    channel = create(:channel_api, account: account)
    target_inbox = channel.inbox
    target_contact = create(:contact, account: account, name: 'dest', phone_number: '+5566988776655')
    conversation.contact.update!(name: 'trigger person')

    expect do
      described_class.new(
        account: account,
        rule: rule,
        conversation: conversation,
        inbox_id: target_inbox.id,
        contact_id: target_contact.id,
        message_template: 'Hi {{contact.name}} via {{rule.name}}'
      ).perform
    end.to change(Message, :count).by(1)

    message = Message.last
    expect(message.content).to eq('Hi Trigger Person via Send contact')
    expect(message.conversation.contact_id).to eq(target_contact.id)
  end
end
