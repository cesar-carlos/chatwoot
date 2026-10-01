require 'rails_helper'

RSpec.describe Custom::Notification::DeliveryAccess do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:notification) { create(:notification, user: user, account: account, primary_actor: conversation) }

  before do
    create(:inbox_member, user: user, inbox: conversation.inbox)
    create(:notification_subscription, :browser_push, user: user)
    allow(VapidService).to receive(:public_key).and_return('public-key')
    allow(WebPush).to receive(:payload_send)
  end

  def deliver
    Notification::PushNotificationService.new(notification: notification).perform
  end

  it 'discards a delivery after inbox access is revoked' do
    notification
    InboxMember.where(inbox_id: conversation.inbox_id, user_id: user.id).destroy_all
    deliver
    expect(WebPush).not_to have_received(:payload_send)
  end

  it 'discards a delivery after account membership is removed' do
    notification
    user.account_users.find_by!(account: account).destroy!
    deliver
    expect(WebPush).not_to have_received(:payload_send)
  end

  it 'discards a delivery after notification access is revoked' do
    notification
    role = create(:custom_role, account: account, permissions: ['conversation_manage'])
    user.account_users.find_by!(account: account).update!(custom_role: role)
    deliver
    expect(WebPush).not_to have_received(:payload_send)
  end

  it 'treats removed preferences as an opt-out without raising' do
    notification
    user.notification_settings.find_by!(account: account).destroy!
    expect { deliver }.not_to raise_error
    expect(WebPush).not_to have_received(:payload_send)
  end

  it 'does not compose content for a revoked recipient' do
    allow(NotificationPolicy).to receive(:new).and_return(instance_double(NotificationPolicy, access?: false))
    expect(notification).not_to receive(:push_message_body)
    deliver
  end

  it 'rechecks the event preference at delivery time' do
    notification
    user.notification_settings.find_by!(account: account).update!(selected_push_flags: [])
    deliver
    expect(WebPush).not_to have_received(:payload_send)
  end

  it 'discards delivery from a suspended account' do
    notification
    account.update!(status: :suspended)
    deliver
    expect(WebPush).not_to have_received(:payload_send)
  end
end
