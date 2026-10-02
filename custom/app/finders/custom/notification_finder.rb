module Custom::NotificationFinder
  private

  def find_all_notifications
    @notifications = Custom::Notification::AccessibleScope.for(user: current_user, account: current_account)
  end
end
