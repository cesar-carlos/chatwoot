require 'rails_helper'

describe Notification::PushNotificationService do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:notification) { create(:notification, user: user, account: user.accounts.first) }
  let(:fcm_double) { instance_double(FCM) }
  let(:fcm_service_double) { instance_double(Notification::FcmService, fcm_client: fcm_double) }

  before do
    create(:inbox_member, user: user, inbox: notification.conversation.inbox)
  end

  describe '#perform' do
    context 'when the push server returns success' do
      before do
        allow(WebPush).to receive(:payload_send).and_return(true)
        allow(Rails.logger).to receive(:info)
        allow(Notification::FcmService).to receive(:new).and_return(fcm_service_double)
        allow(fcm_double).to receive(:send_v1).and_return({ body: { 'results': [] }.to_json })
        allow(GlobalConfigService).to receive(:load).with('FIREBASE_PROJECT_ID', nil).and_return('test_project_id')
        allow(GlobalConfigService).to receive(:load).with('FIREBASE_CREDENTIALS', nil).and_return('test_credentials')
        allow(GlobalConfigService).to receive(:load).with('PWA_ICON_URL', '/favicon-512x512.png').and_return('/pwa-icon.png')
      end

      it 'sends webpush notifications for webpush subscription' do
        with_modified_env VAPID_PUBLIC_KEY: 'test' do
          subscription = create(:notification_subscription, user: notification.user)

          described_class.new(notification: notification).perform

          expect(WebPush).to have_received(:payload_send) do |payload|
            message = JSON.parse(payload[:message]).with_indifferent_access
            expect(message).to include(
              title: notification.push_message_title,
              body: notification.push_message_body,
              icon: '/pwa-icon.png',
              account_id: notification.account_id,
              user_id: notification.user_id,
              notification_id: notification.id
            )
            expect(payload).to include(ttl: 1.day.to_i, urgency: 'high')
          end
          expect(Notification::FcmService).not_to have_received(:new)
          expect(Rails.logger).to have_received(:info)
            .with("Browser push accepted user_id=#{user.id} subscription_id=#{subscription.id} type=browser_push result=accepted")
        end
      end

      it 'sends a fcm notification for firebase subscription' do
        with_modified_env ENABLE_PUSH_RELAY_SERVER: 'false' do
          subscription = create(:notification_subscription, user: notification.user, subscription_type: 'fcm')

          described_class.new(notification: notification).perform
          expect(Notification::FcmService).to have_received(:new)
          expect(fcm_double).to have_received(:send_v1)
          expect(WebPush).not_to have_received(:payload_send)
          expect(Rails.logger).to have_received(:info)
            .with("FCM push accepted user_id=#{user.id} subscription_id=#{subscription.id} type=fcm result=accepted")
        end
      end
    end
  end

  context 'when the push server returns error' do
    it 'sends webpush notifications for webpush subscription' do
      with_modified_env VAPID_PUBLIC_KEY: 'test' do
        mock_response = instance_double(Net::HTTPResponse, body: 'Subscription is invalid')
        mock_host = 'fcm.googleapis.com'

        allow(WebPush).to receive(:payload_send).and_raise(WebPush::InvalidSubscription.new(mock_response, mock_host))
        allow(Rails.logger).to receive(:info)

        subscription = create(:notification_subscription, :browser_push, user: notification.user)

        expect(Rails.logger).to receive(:info) do |message|
          expect(message).to include('WebPush subscription expired')
        end

        described_class.new(notification: notification).perform
        expect { subscription.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
