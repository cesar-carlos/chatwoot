module Custom::SuperAdmin::AppConfigsController
  private

  def custom_branding_options
    super + %w[PWA_ICON_192_URL PWA_ICON_URL PWA_ICON_192_MASKABLE_URL PWA_ICON_MASKABLE_URL PWA_APPLE_TOUCH_ICON_URL
               PWA_FAVICON_URL]
  end
end
