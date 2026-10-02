module Custom::Api::V1::Accounts::NotificationsController
  def read_all
    if params[:primary_actor_type].present? && @primary_actor.nil?
      return render json: { error: 'Invalid conversation' }, status: :unprocessable_entity
    end

    result = Custom::Notification::BulkReadService.perform(user: current_user, account: Current.account, conversation: @primary_actor)
    render json: result || { account_id: Current.account.id, through_notification_id: 0 }
  end

  private

  def fetch_notification
    @notification = Custom::Notification::AccessibleScope.for(user: current_user, account: Current.account).find(params[:id])
  end
end
