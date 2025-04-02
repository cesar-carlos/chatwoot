class Api::V1::ProfilesController < Api::V1::BaseController
  before_action :set_user

  def show
    @user = current_user
    render json: @user
  end

  def update
    @user = current_user
    if @user.update(profile_params)
      render json: @user
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def avatar
    @user.avatar.attachment.destroy! if @user.avatar.attached?
    @user.reload
  end

  def auto_offline
    @user.account_users.find_by!(account_id: auto_offline_params[:account_id]).update!(auto_offline: auto_offline_params[:auto_offline] || false)
  end

  def availability
    @user.account_users.find_by!(account_id: availability_params[:account_id]).update!(availability: availability_params[:availability])
  end

  def set_active_account
    account_user = @user.account_users.find_by(account_id: params[:account_id])
    if account_user
      account_user.update(active_at: Time.now.utc)
      head :ok
    else
      render json: { error: 'Account not found' }, status: :not_found
    end
  end

  def resend_confirmation
    @user.send_confirmation_instructions unless @user.confirmed?
    head :ok
  end

  private

  def set_user
    @user = current_user
  end

  def availability_params
    params.require(:profile).permit(:account_id, :availability)
  end

  def auto_offline_params
    params.require(:profile).permit(:account_id, :auto_offline)
  end

  def profile_params
    params.require(:profile).permit(
      :name,
      :display_name,
      :email,
      :password,
      :password_confirmation,
      :avatar,
      :groq_token,
      :wavoip_token
    )
  end

  def custom_attributes_params
    params.require(:profile).permit(:phone_number)
  end

  def password_params
    params.require(:profile).permit(
      :current_password,
      :password,
      :password_confirmation
    )
  end
end
