require 'rails_helper'
require 'mini_magick'

RSpec.describe Custom::WebAppManifestBuilder do
  describe '#perform' do
    it 'builds a white-label standalone manifest from installation config' do
      allow(GlobalConfig).to receive(:get).with(*described_class::CONFIG_KEYS).and_return(
        {
          'INSTALLATION_NAME' => 'Se7e Sistemas Webchat',
          'BRAND_NAME' => 'Se7e Sistemas',
          'PWA_ICON_192_URL' => '/brand-assets/pwa-se7e-v2-192.png',
          'PWA_ICON_URL' => '/brand-assets/pwa-se7e-v2-512.png',
          'PWA_ICON_192_MASKABLE_URL' => '/brand-assets/pwa-se7e-v2-192-maskable.png',
          'PWA_ICON_MASKABLE_URL' => '/brand-assets/pwa-se7e-v2-512-maskable.png'
        }
      )

      manifest = described_class.new.perform

      expect(manifest).to include(
        id: '/',
        name: 'Se7e Sistemas Webchat',
        short_name: 'Se7e Sistemas',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        prefer_related_applications: false
      )
      expect(manifest[:icons]).to contain_exactly(
        { src: '/brand-assets/pwa-se7e-v2-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
        { src: '/brand-assets/pwa-se7e-v2-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
        { src: '/brand-assets/pwa-se7e-v2-192-maskable.png', sizes: '192x192', type: 'image/png', purpose: 'maskable' },
        { src: '/brand-assets/pwa-se7e-v2-512-maskable.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' }
      )
    end

    it 'uses stable defaults when optional branding values are blank' do
      allow(GlobalConfig).to receive(:get).and_return(
        { 'INSTALLATION_NAME' => nil, 'BRAND_NAME' => nil, 'PWA_ICON_192_URL' => nil, 'PWA_ICON_URL' => nil,
          'PWA_ICON_192_MASKABLE_URL' => nil, 'PWA_ICON_MASKABLE_URL' => nil }
      )

      manifest = described_class.new.perform

      expect(manifest[:name]).to eq('Chatwoot')
      expect(manifest[:short_name]).to eq('Chatwoot')
      expect(manifest.dig(:icons, 0, :src)).to eq('/android-icon-192x192.png')
      expect(manifest.dig(:icons, 1, :src)).to eq('/favicon-512x512.png')
      expect(manifest[:icons].pluck(:purpose)).to eq(['any maskable', 'any maskable'])
    end
  end

  context 'with packaged PWA icons' do
    {
      'pwa-se7e-v2-192.png' => [192, false],
      'pwa-se7e-v2-512.png' => [512, false],
      'pwa-se7e-v2-192-maskable.png' => [192, true],
      'pwa-se7e-v2-512-maskable.png' => [512, true],
      'pwa-se7e-v2-apple-touch-180.png' => [180, true]
    }.each do |filename, (expected_size, opaque)|
      it "validates #{filename}" do
        image = MiniMagick::Image.open(Rails.public_path.join('brand-assets', filename))
        expect(image.type).to eq('PNG')
        expect(image.dimensions).to eq([expected_size, expected_size])
        expect(image['%[opaque]']).to eq(opaque.to_s)
      end
    end

    [192, 512].each do |size|
      it "keeps the #{size}px maskable logo inside the minimum safe circle" do
        image = MiniMagick::Image.open(Rails.public_path.join("brand-assets/pwa-se7e-v2-#{size}-maskable.png"))
        center = (image.width - 1) / 2.0
        light_pixels = 0
        outside_pixels = 0
        image.get_pixels.each_with_index do |row, y|
          row.each_with_index do |pixel, x|
            next unless pixel.first(3).all? { |channel| channel > 180 }

            light_pixels += 1
            outside_pixels += 1 if Math.hypot(x - center, y - center) > image.width * 0.4
          end
        end

        expect(light_pixels).to be_positive
        expect(outside_pixels).to be_zero
      end
    end

    it 'packages a non-empty multi-size favicon' do
      favicon = Rails.public_path.join('brand-assets/pwa-se7e-v2-favicon.ico')
      expect(File.size(favicon)).to be_positive
      expect(MiniMagick::Image.open(favicon).type).to eq('ICO')
    end

    it 'fills the root Apple Touch fallback with the versioned artwork' do
      expect(Rails.public_path.join('apple-touch-icon.png').binread).to eq(
        Rails.public_path.join('brand-assets/pwa-se7e-v2-apple-touch-180.png').binread
      )
    end
  end
end
