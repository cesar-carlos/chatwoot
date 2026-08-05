# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Message::LiquidRuleContext do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'john doe', phone_number: '+5566999000111') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:automation_rule) { create(:automation_rule, account: account, name: 'Boas vindas') }

  after { Current.reset }

  it 'interpolates rule.name when Current.executed_by is an AutomationRule' do
    Current.executed_by = automation_rule

    message = conversation.messages.create!(
      account: account,
      inbox: inbox,
      message_type: :outgoing,
      content: 'Rule: {{rule.name}} — hi {{contact.name}}'
    )

    expect(message.content).to eq('Rule: Boas vindas — hi John Doe')
  end

  it 'renders empty rule.name when no automation is executing' do
    message = conversation.messages.create!(
      account: account,
      inbox: inbox,
      message_type: :outgoing,
      content: 'Rule: {{rule.name}}'
    )

    expect(message.content).to eq('Rule: ')
  end

  it 'interpolates macro.name when Current.executed_by is a Macro' do
    macro = create(:macro, account: account, name: 'Macro Y')
    Current.executed_by = macro

    message = conversation.messages.create!(
      account: account,
      inbox: inbox,
      message_type: :outgoing,
      content: 'Macro: {{macro.name}}'
    )

    expect(message.content).to eq('Macro: Macro Y')
  end

  it 'resolves contact.phone via FORK alias' do
    message = conversation.messages.create!(
      account: account,
      inbox: inbox,
      message_type: :outgoing,
      content: 'Phone {{contact.phone}} / {{contact.phone_number}}'
    )

    expect(message.content).to eq('Phone +5566999000111 / +5566999000111')
  end
end
