# frozen_string_literal: true

module Custom::Api::V1::Accounts::AgentsController
  private

  def associate_agent_with_custom_role
    super
    demote_custom_role_user_to_agent
  end

  # Custom role is an agent with extra permissions. It must not keep administrator.
  def demote_custom_role_user_to_agent
    return if params[:custom_role_id].blank?
    return unless Current.account.feature_enabled?('custom_roles')

    account_user = @agent&.current_account_user
    return if account_user.blank? || account_user.agent?

    account_user.update!(role: :agent)
    Current.account.update_cache_key('inbox')
  end
end
