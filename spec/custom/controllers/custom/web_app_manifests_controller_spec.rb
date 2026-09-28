require 'rails_helper'

RSpec.describe 'White-label web app manifest', type: :request do
  let(:manifest) do
    {
      id: '/', name: 'Se7e Sistemas Webchat', short_name: 'Se7e Sistemas', start_url: '/', scope: '/', display: 'standalone',
      background_color: '#2781F6', theme_color: '#2781F6', icons: []
    }
  end
  let(:builder) { instance_double(Custom::WebAppManifestBuilder, perform: manifest) }

  before do
    allow(Custom::WebAppManifestBuilder).to receive(:new).and_return(builder)
  end

  it 'serves the canonical web manifest without authentication' do
    get '/manifest.webmanifest'

    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq('application/manifest+json')
    expect(JSON.parse(response.body)).to include('name' => 'Se7e Sistemas Webchat', 'display' => 'standalone')
    expect(response.headers['Cache-Control']).to include('max-age=300', 'public')
  end

  it 'keeps the legacy manifest URL compatible' do
    get '/manifest.json'

    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)['id']).to eq('/')
  end
end
