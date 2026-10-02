# frozen_string_literal: true

class Custom::Notification::BrowserPushLogContext
  APPLE_REASONS = %w[
    BadJwtToken BadTtl BadUrgency BadWebPushRequest BadWebPushTopic
    VapidPkHashMismatch BadAuthorizationHeader BadCryptoKey BadEncryptionHeader
    BadRequest InvalidProviderToken ExpiredProviderToken TooManyRequests
    Unregistered PayloadTooLarge InternalServerError ServiceUnavailable Shutdown
  ].freeze

  def self.build(user_id:, subscription:, error: nil)
    context = "user_id=#{user_id} subscription_id=#{subscription.id} type=#{subscription.subscription_type} " \
              "provider=#{provider(subscription)} result=#{error ? 'failed' : 'accepted'}"
    return context unless error

    context += " error_class=#{error.class.name}"
    response = error.respond_to?(:response) ? error.response : nil
    return context unless response

    code = response.code.to_s
    context += " http_status=#{code}" if code.match?(/\A\d{3}\z/)
    reason = response_reason(response)
    context += " provider_reason=#{reason}" if reason
    context
  end

  def self.provider(subscription)
    host = URI.parse(subscription.subscription_attributes['endpoint'].to_s).host.to_s
    return 'apple' if host.end_with?('.push.apple.com')
    return 'google' if host == 'fcm.googleapis.com'
    return 'microsoft' if host.end_with?('.notify.windows.com')
    return 'mozilla' if host.end_with?('.push.services.mozilla.com')

    'other'
  rescue URI::InvalidURIError
    'other'
  end

  def self.response_reason(response)
    data = JSON.parse(response.body.to_s)
    return unless data.is_a?(Hash)

    reason = data['reason']
    APPLE_REASONS.include?(reason) ? reason : nil
  rescue JSON::ParserError, TypeError
    nil
  end
  private_class_method :provider, :response_reason
end
