require 'rails_helper'

RSpec.describe AgentNotifications::ConversationNotificationsMailer do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:team) { create(:team, account: account, allow_auto_assign: false) }
  let(:conversation) { create(:conversation, account: account, team: team) }
  let(:notification) do
    create(:notification, account: account, user: user, primary_actor: conversation, notification_type: :team_conversation_assignment)
  end
  let(:mail) { described_class.with(account: account).team_conversation_assignment(conversation, user, notification).deliver_now }

  before do
    team.members << user
    user.notification_settings.find_by!(account: account).update!(selected_email_flags: ['email_team_conversation_assignment'])
  end

  it 'renders the team title, conversation link and notification preferences footer' do
    with_modified_env SMTP_ADDRESS: 'test.invalid' do
      expect(mail.subject).to include(team.name, conversation.display_id.to_s)
      expect(mail.to).to eq([user.email])
      expect(mail.body.encoded).to include("/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
      expect(mail.body.encoded).to include("/app/accounts/#{account.id}/profile/settings")
    end
  end

  it 'checks eligibility again when a queued email is rendered' do
    notification
    conversation.update!(assignee: user)
    with_modified_env SMTP_ADDRESS: 'test.invalid' do
      expect(mail).to be_nil
    end
  end

  it 'checks opt-out again when a queued email is rendered' do
    notification
    user.notification_settings.find_by!(account: account).update!(selected_email_flags: [])
    with_modified_env SMTP_ADDRESS: 'test.invalid' do
      expect(mail).to be_nil
    end
  end
end
