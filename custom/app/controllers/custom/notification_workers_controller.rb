class Custom::NotificationWorkersController < PublicController
  def show
    response.headers['Cache-Control'] = 'no-cache'
    send_file Rails.root.join('custom/app/javascript/dashboard/helper/notificationWorker.js'),
              type: 'application/javascript', disposition: 'inline'
  end
end
