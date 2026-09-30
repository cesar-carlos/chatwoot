require 'rails_helper'

RSpec.describe 'Dashboard PWA metadata', type: :request do
  it 'renders installability metadata when DISPLAY_MANIFEST is false' do
    allow(GlobalConfig).to receive(:get).and_call_original
    allow(GlobalConfig).to receive(:get).with(*DashboardController::GLOBAL_CONFIG_KEYS).and_return(
      {
        'DISPLAY_MANIFEST' => false,
        'INSTALLATION_NAME' => 'Se7e Sistemas',
        'PWA_ICON_192_URL' => '/brand-assets/pwa-icon-se7e-192.png'
      }
    )

    get '/app/login'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('<link rel="manifest" href="/manifest.webmanifest">')
    expect(response.body).to include('<meta name="theme-color" content="#2781F6">')
    expect(response.body).to include('<meta name="apple-mobile-web-app-capable" content="yes">')
    expect(response.body).to include('<meta name="apple-mobile-web-app-title" content="Se7e Sistemas">')
    expect(response.body).to include(
      '<link rel="apple-touch-icon" sizes="192x192" href="/brand-assets/pwa-icon-se7e-192.png">'
    )
  end
end
