# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::AutomationRuleListener do
  let(:listener) { AutomationRuleListener.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conditions_filter_service) { instance_double(AutomationRules::ConditionsFilterService) }
  let(:action_service) { instance_double(AutomationRules::ActionService, perform: true) }

  before do
    allow(AutomationRules::ConditionsFilterService).to receive(:new).and_return(conditions_filter_service)
    allow(conditions_filter_service).to receive(:perform).and_return(true)
    allow(AutomationRules::ActionService).to receive(:new).and_return(action_service)
  end

  describe 'WhatsApp group conversations' do
    let(:group_jid) { '120363012345678901@g.us' }
    let(:contact) { create(:contact, account: account, phone_number: nil, identifier: group_jid) }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: group_jid) }
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    end

    it 'skips conversation_created for group conversations' do
      create(:automation_rule, event_name: 'conversation_created', account: account)
      event = Events::Base.new(
        'conversation_created',
        Time.zone.now,
        { conversation: conversation, changed_attributes: {} }
      )

      listener.conversation_created(event)

      expect(AutomationRules::ActionService).not_to have_received(:new)
    end

    it 'skips message_created for group conversations' do
      create(:automation_rule, event_name: 'message_created', account: account)
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
      event = Events::Base.new(
        'message_created',
        Time.zone.now,
        { message: message, changed_attributes: {} }
      )

      listener.message_created(event)

      expect(AutomationRules::ActionService).not_to have_received(:new)
    end
  end

  describe '1:1 conversations' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    it 'still runs conversation_created for non-group conversations' do
      automation_rule = create(:automation_rule, event_name: 'conversation_created', account: account)
      event = Events::Base.new(
        'conversation_created',
        Time.zone.now,
        { conversation: conversation, changed_attributes: { status: %w[nil Open] } }
      )

      listener.conversation_created(event)

      expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      expect(action_service).to have_received(:perform)
    end
  end
end
