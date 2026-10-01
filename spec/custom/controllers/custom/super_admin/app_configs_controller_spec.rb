require 'rails_helper'

RSpec.describe Custom::SuperAdmin::AppConfigsController do
  it 'extends the Enterprise custom branding options with the PWA icon' do
    controller = SuperAdmin::AppConfigsController.new

    expect(controller.send(:custom_branding_options)).to include(
      'PWA_ICON_192_URL', 'PWA_ICON_URL', 'PWA_ICON_192_MASKABLE_URL', 'PWA_ICON_MASKABLE_URL',
      'PWA_APPLE_TOUCH_ICON_URL', 'PWA_FAVICON_URL'
    )
  end
end
