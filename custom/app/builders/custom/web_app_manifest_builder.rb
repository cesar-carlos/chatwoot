class Custom::WebAppManifestBuilder
  DEFAULT_NAME = 'Chatwoot'.freeze
  DEFAULT_ICON_192_URL = '/android-icon-192x192.png'.freeze
  DEFAULT_ICON_URL = '/favicon-512x512.png'.freeze
  THEME_COLOR = '#2781F6'.freeze

  def perform
    config = GlobalConfig.get('INSTALLATION_NAME', 'BRAND_NAME', 'PWA_ICON_192_URL', 'PWA_ICON_URL')
    installation_name = config['INSTALLATION_NAME'].presence || DEFAULT_NAME

    {
      id: '/',
      name: installation_name,
      short_name: config['BRAND_NAME'].presence || installation_name,
      start_url: '/',
      scope: '/',
      display: 'standalone',
      prefer_related_applications: false,
      background_color: THEME_COLOR,
      theme_color: THEME_COLOR,
      icons: [
        { src: config['PWA_ICON_192_URL'].presence || DEFAULT_ICON_192_URL, sizes: '192x192', type: 'image/png', purpose: 'any maskable' },
        { src: config['PWA_ICON_URL'].presence || DEFAULT_ICON_URL, sizes: '512x512', type: 'image/png', purpose: 'any maskable' }
      ]
    }
  end
end
