require 'rails_helper'
require 'mini_magick'

RSpec.describe Custom::WebAppManifestBuilder do
  describe '#perform' do
    it 'builds a white-label standalone manifest from installation config' do
      allow(GlobalConfig).to receive(:get).with('INSTALLATION_NAME', 'BRAND_NAME', 'PWA_ICON_192_URL', 'PWA_ICON_URL').and_return(
        {
          'INSTALLATION_NAME' => 'Se7e Sistemas Webchat',
          'BRAND_NAME' => 'Se7e Sistemas',
          'PWA_ICON_192_URL' => '/brand-assets/pwa-icon-se7e-192.png',
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
        display: 'standalone',
        prefer_related_applications: false
      )
      expect(manifest[:icons]).to contain_exactly(
        { src: '/brand-assets/pwa-icon-se7e-192.png', sizes: '192x192', type: 'image/png', purpose: 'any maskable' },
        { src: '/brand-assets/pwa-icon-se7e-512.png', sizes: '512x512', type: 'image/png', purpose: 'any maskable' }
      )
    end

    it 'uses stable defaults when optional branding values are blank' do
      allow(GlobalConfig).to receive(:get).and_return(
        { 'INSTALLATION_NAME' => nil, 'BRAND_NAME' => nil, 'PWA_ICON_192_URL' => nil, 'PWA_ICON_URL' => nil }
      )

      manifest = described_class.new.perform

      expect(manifest[:name]).to eq('Chatwoot')
      expect(manifest[:short_name]).to eq('Chatwoot')
      expect(manifest.dig(:icons, 0, :src)).to eq('/android-icon-192x192.png')
      expect(manifest.dig(:icons, 1, :src)).to eq('/favicon-512x512.png')
    end
  end

  context 'with packaged PWA icons' do
    {
      'pwa-icon-se7e-192.png' => 192,
      'pwa-icon-se7e-512.png' => 512
    }.each do |filename, expected_size|
      it "validates #{filename} for regular and maskable use" do
        image = MiniMagick::Image.open(Rails.public_path.join('brand-assets', filename))
        pixels = image.get_pixels
        background = pixels.first.first.first(3)
        center = (expected_size - 1) / 2.0
        content_outside_safe_circle = false
        pixels.each_with_index do |row, y|
          row.each_with_index do |pixel, x|
            next unless Math.hypot(x - center, y - center) > expected_size * 0.4

            content_outside_safe_circle ||= pixel.first(3).zip(background).any? { |value, base| (value - base).abs > 5 }
          end
        end

        expect(image.type).to eq('PNG')
        expect(image.dimensions).to eq([expected_size, expected_size])
        expect(image['%[opaque]']).to eq('true')
        expect(content_outside_safe_circle).to be(false)
      end
    end
  end
end
