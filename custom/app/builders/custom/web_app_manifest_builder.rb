class Custom::WebAppManifestBuilder
  DEFAULT_NAME = 'Chatwoot'.freeze
  DEFAULT_ICON_192_URL = '/android-icon-192x192.png'.freeze
  DEFAULT_ICON_URL = '/favicon-512x512.png'.freeze
  THEME_COLOR = '#2781F6'.freeze
  CONFIG_KEYS = %w[INSTALLATION_NAME BRAND_NAME PWA_ICON_192_URL PWA_ICON_URL PWA_ICON_192_MASKABLE_URL PWA_ICON_MASKABLE_URL].freeze

  def perform
    config = GlobalConfig.get(*CONFIG_KEYS)
    installation_name = config['INSTALLATION_NAME'].presence || DEFAULT_NAME
    icons = icon_entries(config['PWA_ICON_192_URL'], config['PWA_ICON_192_MASKABLE_URL'], DEFAULT_ICON_192_URL, 192) +
            icon_entries(config['PWA_ICON_URL'], config['PWA_ICON_MASKABLE_URL'], DEFAULT_ICON_URL, 512)

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
      icons: icons
    }
  end

  private

  def icon_entries(regular_url, maskable_url, default_url, size)
    maskable_url = maskable_url.presence
    regular = { src: regular_url.presence || default_url, sizes: "#{size}x#{size}", type: 'image/png',
                purpose: maskable_url ? 'any' : 'any maskable' }
    return [regular] unless maskable_url

    [regular, { src: maskable_url, sizes: "#{size}x#{size}", type: 'image/png', purpose: 'maskable' }]
  end
end
