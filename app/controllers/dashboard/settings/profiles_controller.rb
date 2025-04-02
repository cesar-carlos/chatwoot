class Dashboard::Settings::ProfilesController < Dashboard::BaseController
  def show
    @user = current_user
  end

  def update
    @user = current_user
    if @user.update(profile_params)
      redirect_to dashboard_settings_profile_path, notice: t('.success')
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:user).permit(
      :name,
      :display_name,
      :email,
      :password,
      :password_confirmation,
      :avatar
    )
  end
end
