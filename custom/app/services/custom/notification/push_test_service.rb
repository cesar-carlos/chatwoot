module Custom::Notification::PushTestService
  private

  def test_browser_push(subscription)
    return result(subscription, 'browser_push', :skipped, 'VAPID keys not configured') unless VapidService.public_key

    WebPush.payload_send(**browser_push_payload(subscription))
    Rails.logger.info("Browser push test accepted #{Custom::Notification::BrowserPushLogContext.build(user_id: user.id, subscription: subscription)}")
    result(subscription, 'browser_push', :success, 'Accepted by push service; device display is not confirmed')
  rescue StandardError => e
    Rails.logger.warn(
      "Browser push test failed #{Custom::Notification::BrowserPushLogContext.build(user_id: user.id, subscription: subscription, error: e)}"
    )
    subscription.destroy! if e.is_a?(WebPush::ExpiredSubscription) || e.is_a?(WebPush::InvalidSubscription)
    result(subscription, 'browser_push', :failure, 'Push service did not accept the test notification')
  end

  def browser_push_payload(subscription)
    payload = super
    message = JSON.parse(payload[:message]).merge(
      'body' => resolved_body,
      'icon' => GlobalConfigService.load('PWA_ICON_URL', '/favicon-512x512.png')
    )

    payload.merge(
      message: Custom::Notification::BrowserPushPayload.generate(message),
      **Custom::Notification::PushNotificationService::WEB_PUSH_OPTIONS
    )
  end
end
