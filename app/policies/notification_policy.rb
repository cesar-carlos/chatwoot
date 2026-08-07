class NotificationPolicy < ApplicationPolicy
  def access?
    true
  end
end

NotificationPolicy.prepend_mod_with('NotificationPolicy')
