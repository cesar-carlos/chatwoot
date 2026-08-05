# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AutomationRules::ActionService send_email_to_team liquid' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'jane doe') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:team) { create(:team, account: account) }
  let(:rule) do
    create(
      :automation_rule,
      account: account,
      actions: [{
        'action_name' => 'send_email_to_team',
        'action_params' => [{ 'team_ids' => [team.id], 'message' => 'Alert {{contact.name}}' }]
      }]
    )
  end

  before do
    create(:team_member, team: team, user: create(:user, account: account))
  end

  it 'interpolates liquid in the team email message' do
    expect(TeamNotifications::AutomationNotificationMailer).to receive(:conversation_creation).with(
      conversation,
      team,
      'Alert Jane Doe'
    ).and_return(instance_double(ActionMailer::MessageDelivery, deliver_now: true))

    AutomationRules::ActionService.new(rule, account, conversation).perform
  end
end
