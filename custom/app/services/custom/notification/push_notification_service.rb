module Custom::Notification::PushNotificationService
  WEB_PUSH_OPTIONS = {
    ttl: 1.day.to_i,
    urgency: 'high',
    ssl_timeout: 5,
    open_timeout: 5,
    read_timeout: 5
  }.freeze

  private

  def user_subscribed_to_notification?
    eligible = Custom::Notification::DeliveryAccess.allowed?(notification) &&
               notification_settings.find_by(account_id: notification.account_id)&.public_send("push_#{notification.notification_type}?")
    unless eligible
      Rails.logger.info("Push discarded user_id=#{user.id} account_id=#{notification.account_id} notification_id=#{notification.id} result=discarded")
    end

    eligible || false
  end

  def push_message
    super.merge(
      body: notification.push_message_body,
      icon: GlobalConfigService.load('PWA_ICON_URL', '/favicon-512x512.png'),
      user_id: user.id,
      account_id: notification.account_id,
      notification_id: notification.id,
      action_labels: notification.notification_action_labels
    )
  end

  def browser_push_payload(subscription)
    super.merge(**WEB_PUSH_OPTIONS)
  end

  def send_browser_push(subscription)
    return unless can_send_browser_push?(subscription)

    WebPush.payload_send(**browser_push_payload(subscription))
    Rails.logger.info("Browser push accepted #{push_log_context(subscription)}")
  rescue StandardError => e
    handle_browser_push_error(e, subscription)
  end

  def handle_browser_push_error(error, subscription)
    context = push_log_context(subscription, error)

    case error
    when WebPush::ExpiredSubscription, WebPush::InvalidSubscription, WebPush::Unauthorized
      Rails.logger.info("WebPush subscription expired #{context}")
      subscription.destroy!
    when WebPush::TooManyRequests
      Rails.logger.warn("WebPush rate limited #{context}")
    when Errno::ECONNRESET, Net::OpenTimeout, Net::ReadTimeout, Socket::ResolutionError
      Rails.logger.error("WebPush operation error #{context}")
    else
      Rails.logger.error("WebPush failed #{context}")
    end
  end

  def remove_subscription_if_error(subscription, response)
    if JSON.parse(response[:body])['results']&.first&.keys&.include?('error')
      subscription.destroy!
    else
      Rails.logger.info("FCM push accepted #{push_log_context(subscription)}")
    end
  end

  def push_log_context(subscription, error = nil)
    context = "user_id=#{user.id} subscription_id=#{subscription.id} type=#{subscription.subscription_type} result=#{error ? 'failed' : 'accepted'}"
    error ? "#{context} error_class=#{error.class.name}" : context
  end
end
