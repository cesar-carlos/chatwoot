require 'rails_helper'

RSpec.describe 'Dashboard PWA metadata', type: :request do
  it 'renders installability metadata when DISPLAY_MANIFEST is false' do
    allow(GlobalConfig).to receive(:get).and_call_original
    allow(GlobalConfig).to receive(:get).with(*DashboardController::GLOBAL_CONFIG_KEYS).and_return(
      {
        'DISPLAY_MANIFEST' => false,
        'INSTALLATION_NAME' => 'Se7e Sistemas',
        'PWA_ICON_192_URL' => '/brand-assets/pwa-se7e-v2-192.png',
        'PWA_APPLE_TOUCH_ICON_URL' => '/brand-assets/pwa-se7e-v2-apple-touch-180.png',
        'PWA_FAVICON_URL' => '/brand-assets/pwa-se7e-v2-favicon.ico'
      }
    )

    get '/app/login'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('<link rel="manifest" href="/manifest.webmanifest">')
    expect(response.body).to include('<meta name="theme-color" content="#2781F6">')
    expect(response.body).to include('<meta name="apple-mobile-web-app-capable" content="yes">')
    expect(response.body).to include('<meta name="apple-mobile-web-app-title" content="Se7e Sistemas">')
    expect(response.body).to include(
      '<link rel="apple-touch-icon" sizes="180x180" href="/brand-assets/pwa-se7e-v2-apple-touch-180.png">'
    )
    expect(response.body).to include('<link rel="icon" sizes="any" href="/brand-assets/pwa-se7e-v2-favicon.ico">')
  end

  it 'declares the correct size when using the existing Apple icon fallback' do
    allow(GlobalConfig).to receive(:get).and_call_original
    allow(GlobalConfig).to receive(:get).with(*DashboardController::GLOBAL_CONFIG_KEYS).and_return(
      {
        'DISPLAY_MANIFEST' => false,
        'PWA_ICON_192_URL' => '/brand-assets/pwa-icon-se7e-192.png',
        'PWA_APPLE_TOUCH_ICON_URL' => nil,
        'PWA_FAVICON_URL' => nil,
        'LOGO_THUMBNAIL' => '/favicon.png'
      }
    )

    get '/app/login'

    expect(response.body).to include('<link rel="apple-touch-icon" sizes="192x192" href="/brand-assets/pwa-icon-se7e-192.png">')
    expect(response.body).to include('<link rel="icon" sizes="any" href="/favicon.png">')
  end
end
