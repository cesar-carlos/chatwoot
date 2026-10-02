require 'rails_helper'

RSpec.describe Notification do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account, allow_auto_assign: false) }
  let(:user) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, team: team) }
  let(:notification) do
    create(:notification, notification_type: :team_conversation_assignment, account: account, user: user, primary_actor: conversation)
  end

  it 'appends the enum without renumbering existing notification flags' do
    expect(described_class.notification_types).to include('conversation_assignment' => 2, 'voice_call_incoming' => 9,
                                                          'team_conversation_assignment' => 10)
    settings = user.notification_settings.find_by!(account: account)
    expect(settings.all_push_flags).to include(:push_team_conversation_assignment)
    expect(settings.all_email_flags).to include(:email_team_conversation_assignment)
    expect(settings.push_team_conversation_assignment?).to be(false)
    expect(settings.email_team_conversation_assignment?).to be(false)
  end

  it 'renders the team and conversation in both supported translations' do
    %w[en pt_BR].each do |locale|
      user.update!(ui_settings: { 'locale' => locale })
      I18n.with_locale(locale) do
        expect(notification.push_message_title).to include(team.name, conversation.display_id.to_s)
        expect(notification.push_message_title).not_to include('Translation missing')
        expect(notification.push_event_data[:notification_title]).to eq(notification.push_message_title)
      end
    end
  end

  it 'uses the recipient language even when the push job runs in another locale' do
    user.update!(ui_settings: { 'locale' => 'pt_BR' })
    I18n.with_locale(:en) do
      expect(notification.push_message_title).to include('foi atribuída ao seu time')
    end
  end

  it 'includes the latest incoming message body for push and popup consumers' do
    message = create(:message, conversation: conversation, account: account, sender: conversation.contact, content: 'Please help')
    expect(notification.push_message_body).to include(message.content)
    expect(notification.push_event_data[:push_message_body]).to eq(notification.push_message_body)
  end
end
