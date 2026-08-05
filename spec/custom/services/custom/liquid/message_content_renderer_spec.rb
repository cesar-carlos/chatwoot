# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Liquid::MessageContentRenderer do
  let(:account) { create(:account, name: 'Acme Co') }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp Support') }
  let(:contact) { create(:contact, account: account, name: 'john doe', email: 'john@example.com') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:automation_rule) { create(:automation_rule, account: account, name: 'Boas vindas') }
  let(:macro) { create(:macro, account: account, name: 'Macro X') }

  it 'renders contact and conversation liquid drops' do
    result = described_class.render(
      'Hi {{contact.name}} #{{conversation.display_id}}',
      conversation: conversation
    )

    expect(result).to include('John Doe')
    expect(result).to include(conversation.display_id.to_s)
  end

  it 'renders rule.name when executed_by is an AutomationRule' do
    result = described_class.render(
      'Rule={{rule.name}}',
      conversation: conversation,
      executed_by: automation_rule
    )

    expect(result).to eq('Rule=Boas vindas')
  end

  it 'renders macro.name when executed_by is a Macro' do
    result = described_class.render(
      'Macro={{macro.name}}',
      conversation: conversation,
      executed_by: macro
    )

    expect(result).to eq('Macro=Macro X')
  end

  it 'returns blank string for blank template' do
    expect(described_class.render('  ', conversation: conversation)).to eq('')
  end
end
