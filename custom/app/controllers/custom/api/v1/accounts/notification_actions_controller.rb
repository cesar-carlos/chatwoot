class Custom::Api::V1::Accounts::NotificationActionsController < Api::V1::Accounts::BaseController
  def read
    notification = current_user.notifications.where(account_id: Current.account.id).find(params[:notification_id])
    authorize(Notification, :access?)
    authorize(notification.conversation, :show?)
    notification.with_lock do
      notification.update!(read_at: Time.current) unless notification.read_at
    end
    render json: { id: notification.id, account_id: notification.account_id, read_at: notification.read_at }
  end
end
