module Custom::Api::V1::NotificationSubscriptionsController
  def destroy
    identifiers = [params[:endpoint], params[:push_token]]
    valid_identifier = identifiers.count(&:present?) == 1 && identifiers.compact_blank.first.is_a?(String)
    return render json: { error: 'Provide exactly one of endpoint or push_token' }, status: :unprocessable_entity unless valid_identifier

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
