require 'rails_helper'

RSpec.describe Custom::Notification::BulkReadService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let!(:notification) { create(:notification, user: user, account: account, primary_actor: conversation) }

  it 'bounds the database update and broadcasts only to the recipient' do
    later = nil
    scope = user.notifications.where(account_id: account.id, read_at: nil).where(primary_actor: conversation)
    allow(user.notifications).to receive(:where).and_call_original
    allow(user.notifications).to receive(:where).with(account_id: account.id, read_at: nil).and_return(scope)
    allow(scope).to receive(:where).with(primary_actor: conversation).and_return(scope)
    allow(scope).to receive(:where).with(id: ..notification.id).and_call_original
    allow(scope).to receive(:maximum).with(:id).and_wrap_original do |method, *args|
      cutoff = method.call(*args)
      later ||= create(:notification, user: user, account: account, primary_actor: conversation, notification_type: 'conversation_mention')
      cutoff
    end
    result = described_class.perform(user: user, account: account, conversation: conversation)
    expect(notification.reload.read_at).to be_present
    expect(later.reload.read_at).to be_nil
    expect(result).to include(through_notification_id: notification.id, conversation_display_id: conversation.display_id)
    expect(ActionCableBroadcastJob).to have_been_enqueued.with([user.pubsub_token], 'notifications.read', result)
  end

  it 'never updates another recipient or account' do
    other = create(:notification, account: account, primary_actor: conversation)
    described_class.perform(user: user, account: account)
    expect(other.reload.read_at).to be_nil
  end
end
