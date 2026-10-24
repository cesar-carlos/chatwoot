require 'rails_helper'

RSpec.describe 'Notification worker script', type: :request do
  it 'serves the overlay worker without authentication and forces revalidation' do
    get '/notification-worker.js'

    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq('application/javascript')
    expect(response.headers['Cache-Control']).to include('no-cache')
    expect(response.body).to include("addEventListener('push'", "addEventListener('notificationclick'")
  end

  it 'is imported by the classic service worker' do
    expect(Rails.public_path.join('sw.js').read).to include("importScripts('/notification-worker.js')")
  end
end
