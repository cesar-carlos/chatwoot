module Custom::NotificationPolicy
  INBOX_VIEW_PERMISSION = 'inbox_view_manage'.freeze

  def access?
    return true if account_user&.administrator?
    return true if account_user&.agent? && account_user.custom_role_id.blank?

    account_user&.custom_role&.permissions&.include?(INBOX_VIEW_PERMISSION)
  end
end
