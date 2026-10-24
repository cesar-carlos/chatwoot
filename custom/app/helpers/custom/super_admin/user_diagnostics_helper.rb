# frozen_string_literal: true

module Custom::SuperAdmin::UserDiagnosticsHelper
  def browser_push_provider(subscription)
    return em_dash unless subscription.browser_push?

    Custom::Notification::BrowserPushLogContext.provider(subscription)
  end

  def browser_push_synced_at(subscription)
    return em_dash unless subscription.browser_push? && subscription.last_synced_at

    subscription.last_synced_at.strftime('%Y-%m-%d %H:%M')
  end

  def browser_push_delivery(subscription)
    return em_dash unless subscription.browser_push? && subscription.last_push_at

    status = t(
      "super_admin.user_diagnostics.push.delivery_status.#{subscription.last_push_status}",
      default: subscription.last_push_status.to_s
    )
    [status, subscription.last_push_at.strftime('%Y-%m-%d %H:%M'), subscription.last_push_error].compact_blank.join(' · ')
  end

  private

  def em_dash
    '—'
  end
end
