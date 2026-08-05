# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Automation opened_by condition' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      additional_attributes: { 'opened_by' => 'contact' }
    )
  end

  def build_rule(conditions)
    create(
      :automation_rule,
      account: account,
      event_name: 'conversation_opened',
      conditions: conditions,
      actions: [{ 'action_name' => 'add_label', 'action_params' => ['test'] }]
    )
  end

  it 'allows opened_by in AutomationRule conditions_attributes' do
    expect(AutomationRule.new.conditions_attributes).to include('opened_by')
  end

  it 'matches when opened_by equals contact' do
    rule = build_rule(
      [
        {
          'attribute_key' => 'opened_by',
          'filter_operator' => 'equal_to',
          'values' => ['contact'],
          'query_operator' => nil
        }
      ]
    )

    expect(AutomationRules::ConditionsFilterService.new(rule, conversation).perform).to be(true)
  end

  it 'does not match when opened_by is agent' do
    conversation.update!(additional_attributes: { 'opened_by' => 'agent' })
    rule = build_rule(
      [
        {
          'attribute_key' => 'opened_by',
          'filter_operator' => 'equal_to',
          'values' => ['contact'],
          'query_operator' => nil
        }
      ]
    )

    expect(AutomationRules::ConditionsFilterService.new(rule, conversation).perform).to be(false)
  end

  it 'still matches rules without opened_by condition' do
    rule = build_rule(
      [
        {
          'attribute_key' => 'status',
          'filter_operator' => 'equal_to',
          'values' => ['open'],
          'query_operator' => nil
        }
      ]
    )
    conversation.open!

    expect(AutomationRules::ConditionsFilterService.new(rule, conversation).perform).to be(true)
  end

  it 'saves a rule that uses opened_by' do
    rule = build_rule(
      [
        {
          'attribute_key' => 'opened_by',
          'filter_operator' => 'equal_to',
          'values' => ['contact'],
          'query_operator' => nil
        }
      ]
    )

    expect(rule).to be_persisted
    expect(rule.conditions.first['attribute_key']).to eq('opened_by')
  end
end
