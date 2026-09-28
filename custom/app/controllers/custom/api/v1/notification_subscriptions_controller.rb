module Custom::Api::V1::NotificationSubscriptionsController
  def destroy
    notification_subscription = browser_push_subscription || fcm_subscription
    notification_subscription&.destroy!
    head :ok
  end

  private

  def browser_push_subscription
    return if params[:endpoint].blank?

    current_user.notification_subscriptions.browser_push.find_by(
      identifier: params[:endpoint]
    )
  end

  def fcm_subscription
    return if params[:push_token].blank?

    current_user.notification_subscriptions.fcm
                .where(["subscription_attributes->>'push_token' = ?", params[:push_token]])
                .first
  end
end
