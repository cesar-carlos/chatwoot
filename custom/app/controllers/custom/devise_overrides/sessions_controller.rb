# frozen_string_literal: true

module Custom::DeviseOverrides::SessionsController
  private

  def login_page_url(error: nil)
    "#{Custom::FrontendHost.public_base_url(request)}/app/login?error=#{error}"
  end
end

DeviseOverrides::SessionsController.prepend_mod_with('DeviseOverrides::SessionsController')
