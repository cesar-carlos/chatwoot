# frozen_string_literal: true

module Custom::DeviseOverrides::OmniauthCallbacksController
  private

  def sign_up_user
    return redirect_to login_page_url(error: 'no-account-found') unless account_signup_allowed?
    return redirect_to login_page_url(error: 'business-account-only') unless validate_signup_email_is_business_domain?

    create_account_for_user
    set_random_password_if_oauth_user
    token = @resource.send(:set_reset_password_token)
    redirect_to "#{Custom::FrontendHost.public_base_url(request)}/app/auth/password/edit?config=default&reset_password_token=#{token}"
  end

  def login_page_url(error: nil, email: nil, sso_auth_token: nil)
    params = { email: email, sso_auth_token: sso_auth_token }.compact
    params[:error] = error if error.present?

    "#{Custom::FrontendHost.public_base_url(request)}/app/login?#{params.to_query}"
  end
end

DeviseOverrides::OmniauthCallbacksController.prepend_mod_with('DeviseOverrides::OmniauthCallbacksController')
