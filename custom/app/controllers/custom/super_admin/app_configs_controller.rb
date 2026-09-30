module Custom::SuperAdmin::AppConfigsController
  private

  def custom_branding_options
    super + %w[PWA_ICON_192_URL PWA_ICON_URL]
  end
end
