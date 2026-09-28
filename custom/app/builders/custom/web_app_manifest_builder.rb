class Custom::WebAppManifestBuilder
  DEFAULT_NAME = 'Chatwoot'.freeze
  DEFAULT_ICON_URL = '/favicon-512x512.png'.freeze
  THEME_COLOR = '#2781F6'.freeze

  def perform
    config = GlobalConfig.get('INSTALLATION_NAME', 'BRAND_NAME', 'PWA_ICON_URL')
    installation_name = config['INSTALLATION_NAME'].presence || DEFAULT_NAME

    {
      id: '/',
      name: installation_name,
      short_name: config['BRAND_NAME'].presence || installation_name,
      start_url: '/',
      scope: '/',
      display: 'standalone',
      background_color: THEME_COLOR,
      theme_color: THEME_COLOR,
      icons: [{ src: config['PWA_ICON_URL'].presence || DEFAULT_ICON_URL, sizes: '512x512', type: 'image/png', purpose: 'any' }]
    }
  end
end
