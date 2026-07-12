# frozen_string_literal: true

# Resolves the public frontend base URL for the current request so alias hosts
# (e.g. dev-chat.*) behave like the canonical FRONTEND_URL host.
module Custom::FrontendHost
  module_function

  def public_base_url(request = nil)
    from_request = request&.base_url.to_s.delete_suffix('/')
    return from_request if from_request.present?

    ENV.fetch('FRONTEND_URL', '').to_s.delete_suffix('/')
  end
end
