module Custom::Api::V1::NotificationSubscriptionsController
  def create
    unless params[:notification_subscription].is_a?(ActionController::Parameters)
      return render json: { error: 'Invalid subscription parameters' }, status: :unprocessable_entity
    end

    input = notification_subscription_params
    unless %w[browser_push fcm].include?(input[:subscription_type])
      return render json: { error: 'Invalid subscription type' }, status: :unprocessable_entity
    end

    valid = input[:subscription_type] != 'browser_push' || Custom::Notification::BrowserSubscriptionValidator.valid?(input[:subscription_attributes])
    return render json: { error: 'Invalid browser push subscription' }, status: :unprocessable_entity unless valid

    super
  rescue ActionController::ParameterMissing
    render json: { error: 'Invalid subscription parameters' }, status: :unprocessable_entity
  end

  def test
    unless Custom::Notification::BrowserSubscriptionValidator.endpoint_valid?(params[:endpoint])
      return render json: { error: 'Invalid endpoint' }, status: :unprocessable_entity
    end

    subscription = browser_push_subscription
    return head :not_found unless subscription
    return head :too_many_requests unless push_test_allowed?

    result = Notification::PushTestService.new(user: current_user, subscription_ids: [subscription.id]).perform.first
    return head :not_found unless result

    accepted = result[:status] == :success
    render json: { accepted: accepted, message: result[:message] }, status: accepted ? :ok : :bad_gateway
  end

  def destroy
    identifiers = [params[:endpoint], params[:push_token]]
    valid_identifier = identifiers.count(&:present?) == 1 && identifiers.compact_blank.first.is_a?(String)
    return render json: { error: 'Provide exactly one of endpoint or push_token' }, status: :unprocessable_entity unless valid_identifier

    notification_subscription = browser_push_subscription || fcm_subscription
    notification_subscription&.destroy!
    head :ok
  end

  private

  def push_test_allowed?
    key = "browser-push-test:#{current_user.id}:#{Time.current.to_i / 60}"
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, 120) if count == 1
    count <= 3
  end

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
