require 'rails_helper'

RSpec.describe NotificationBuilder do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before do
    create(:inbox_member, user: user, inbox: inbox)
    settings = user.notification_settings.find_by!(account: account)
    settings.selected_email_flags = []
    settings.selected_push_flags = []
    settings.save!
  end

  it 'creates a new-conversation notification with only the popup preference enabled' do
    user.update!(ui_settings: {
                   'popup_notification_flags_by_account' => {
                     account.id.to_s => ['popup_conversation_creation']
                   }
                 })

    expect do
      described_class.new(
        notification_type: 'conversation_creation',
        user: user,
        account: account,
        primary_actor: conversation
      ).perform
    end.to change { user.notifications.count }.by(1)
  end

  it 'honors legacy popup flags when no per-account map exists' do
    user.update!(ui_settings: { 'popup_notification_flags' => ['popup_conversation_creation'] })

    expect do
      described_class.new(
        notification_type: 'conversation_creation',
        user: user,
        account: account,
        primary_actor: conversation
      ).perform
    end.to change { user.notifications.count }.by(1)
  end

  it 'does not use another account or legacy flags when a per-account map exists' do
    user.update!(ui_settings: {
                   'popup_notification_flags' => ['popup_conversation_creation'],
                   'popup_notification_flags_by_account' => {
                     (account.id + 1).to_s => ['popup_conversation_creation']
                   }
                 })

    expect do
      described_class.new(
        notification_type: 'conversation_creation',
        user: user,
        account: account,
        primary_actor: conversation
      ).perform
    end.not_to(change { user.notifications.count })
  end
end
