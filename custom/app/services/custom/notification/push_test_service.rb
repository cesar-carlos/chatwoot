module Custom::Notification::PushTestService
  private

  def test_browser_push(subscription)
    return result(subscription, 'browser_push', :skipped, 'VAPID keys not configured') unless VapidService.public_key

    WebPush.payload_send(**browser_push_payload(subscription))
    Rails.logger.info("Browser push test accepted user_id=#{user.id} subscription_id=#{subscription.id} type=browser_push result=accepted")
    result(subscription, 'browser_push', :success, 'Accepted by push service; device display is not confirmed')
  rescue StandardError => e
    Rails.logger.warn(
      "Browser push test failed user_id=#{user.id} subscription_id=#{subscription.id} type=browser_push result=failed error_class=#{e.class.name}"
    )
    result(subscription, 'browser_push', :failure, 'Push service did not accept the test notification')
  end

  def browser_push_payload(subscription)
    payload = super
    message = JSON.parse(payload[:message]).merge(
      'body' => resolved_body,
      'icon' => GlobalConfigService.load('PWA_ICON_URL', '/favicon-512x512.png')
    )

    payload.merge(
      message: JSON.generate(message),
      **Custom::Notification::PushNotificationService::WEB_PUSH_OPTIONS
    )
  end
end
