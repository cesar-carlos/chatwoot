class DemoteAdministratorsWithCustomRoles < ActiveRecord::Migration[7.1]
  def up
    # A custom role is an agent with extra permissions. Administrator bypasses inbox membership.
    AccountUser.administrator.where.not(custom_role_id: nil).find_each do |account_user|
      account_user.update!(role: :agent)
      account_user.account.update_cache_key('inbox')
    end
  end

  def down; end
end
