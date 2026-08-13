module Custom::NotificationPolicy
  INBOX_VIEW_PERMISSION = 'inbox_view_manage'.freeze

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- admin/agent/custom-role matrix
  def access?
    return true if account_user&.administrator?
    return true if account_user&.agent? && account_user.custom_role_id.blank?

    account_user&.custom_role&.permissions&.include?(INBOX_VIEW_PERMISSION)
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
end
