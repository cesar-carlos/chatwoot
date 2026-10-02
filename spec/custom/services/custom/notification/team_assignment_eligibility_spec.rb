require 'rails_helper'

RSpec.describe Custom::Notification::TeamAssignmentEligibility do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account, allow_auto_assign: false) }
  let(:user) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, team: team) }
  let(:notification) do
    create(:notification, notification_type: :team_conversation_assignment, account: account, user: user, primary_actor: conversation)
  end

  before do
    team.members << user
    user.notification_settings.find_by!(account: account).update!(selected_email_flags: ['email_team_conversation_assignment'],
                                                                  selected_push_flags: ['push_team_conversation_assignment'])
    create(:notification_subscription, :browser_push, user: user)
    allow(VapidService).to receive(:public_key).and_return('test-key')
    allow(WebPush).to receive(:payload_send)
  end

  def push
    Notification::PushNotificationService.new(notification: notification).perform
  end

  def email
    Notification::EmailNotificationService.new(notification: notification).perform
  end

  it 'delivers an eligible team notification using the existing browser push payload' do
    push
    expect(WebPush).to have_received(:payload_send).with(hash_including(ttl: 86_400, urgency: 'high'))
  end

  it 'queues the new mailer action with the notification for a second eligibility check' do
    expect { email }.to have_enqueued_mail(AgentNotifications::ConversationNotificationsMailer, :team_conversation_assignment)
  end

  it 'discards both channels after the user leaves the team even if inbox access remains' do
    notification
    create(:inbox_member, user: user, inbox: conversation.inbox)
    team.team_members.where(user_id: user.id).destroy_all
    push
    expect { email }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
    expect(WebPush).not_to have_received(:payload_send)
  end

  it 'discards a delayed notification after the conversation moves to another team of the same user' do
    notification
    other_team = create(:team, account: account, allow_auto_assign: false)
    other_team.members << user
    conversation.update!(team: other_team)
    push
    expect { email }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
    expect(WebPush).not_to have_received(:payload_send)
  end

  it 'discards both channels if an agent is assigned before delivery' do
    notification
    conversation.update!(assignee: user)
    push
    expect { email }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
    expect(WebPush).not_to have_received(:payload_send)
  end

  it 'does not raise or send if preferences have been removed' do
    notification
    user.notification_settings.find_by!(account: account).destroy!
    expect do
      push
      email
    end.not_to raise_error
    expect(WebPush).not_to have_received(:payload_send)
  end
end
