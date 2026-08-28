# frozen_string_literal: true

module Custom::InboxPolicy
  INBOX_MANAGE_PERMISSION = 'inbox_manage'

  def update?
    administrator_or_assigned_inbox_manager?
  end

  def avatar?
    administrator_or_assigned_inbox_manager?
  end

  def set_agent_bot?
    administrator_or_assigned_inbox_manager?
  end

  def sync_templates?
    administrator_or_assigned_inbox_manager?
  end

  def whatsapp_business_management_token?
    administrator_or_assigned_inbox_manager?
  end

  def health?
    administrator_or_assigned_inbox_manager?
  end

  def reset_secret?
    administrator_or_assigned_inbox_manager?
  end

  def enable_whatsapp_calling?
    administrator_or_assigned_inbox_manager?
  end

  def disable_whatsapp_calling?
    administrator_or_assigned_inbox_manager?
  end

  def set_inbound_calls?
    administrator_or_assigned_inbox_manager?
  end

  def regenerate_wavoip_webhook_key?
    administrator_or_assigned_inbox_manager?
  end

  def manage_members?
    administrator_or_assigned_inbox_manager?
  end

  private

  def administrator_or_assigned_inbox_manager?
    return true if @account_user&.administrator?

    assigned_inbox_manager?
  end

  def assigned_inbox_manager?
    return false if @account_user&.custom_role_id.blank?
    return false unless @account_user.custom_role&.permissions&.include?(INBOX_MANAGE_PERMISSION)
    return false unless record.is_a?(Inbox)

    user.inboxes.where(account_id: record.account_id).exists?(id: record.id)
  end
end
