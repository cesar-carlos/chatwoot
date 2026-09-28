require 'rails_helper'

RSpec.describe Custom::WebAppManifestBuilder do
  describe '#perform' do
    it 'builds a white-label standalone manifest from installation config' do
      allow(GlobalConfig).to receive(:get).with('INSTALLATION_NAME', 'BRAND_NAME', 'PWA_ICON_URL').and_return(
        {
          'INSTALLATION_NAME' => 'Se7e Sistemas Webchat',
          'BRAND_NAME' => 'Se7e Sistemas',
          'PWA_ICON_URL' => '/brand-assets/pwa-icon-se7e-512.png'
        }
      )

      manifest = described_class.new.perform

      expect(manifest).to include(
        id: '/',
        name: 'Se7e Sistemas Webchat',
        short_name: 'Se7e Sistemas',
        start_url: '/',
        scope: '/',
        display: 'standalone'
      )
      expect(manifest[:icons]).to contain_exactly(
        src: '/brand-assets/pwa-icon-se7e-512.png', sizes: '512x512', type: 'image/png', purpose: 'any'
      )
    end

    it 'uses stable defaults when optional branding values are blank' do
      allow(GlobalConfig).to receive(:get).and_return(
        { 'INSTALLATION_NAME' => nil, 'BRAND_NAME' => nil, 'PWA_ICON_URL' => nil }
      )

      manifest = described_class.new.perform

      expect(manifest[:name]).to eq('Chatwoot')
      expect(manifest[:short_name]).to eq('Chatwoot')
      expect(manifest.dig(:icons, 0, :src)).to eq('/favicon-512x512.png')
    end
  end
end
