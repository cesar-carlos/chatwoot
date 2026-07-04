# frozen_string_literal: true

module MessagingProvider::Capabilities
  CAPABILITIES = {
    'evolution' => {
      unlimited_session: true,
      templates_required: false,
      cloud_api: false
    },
    'evolution_go' => {
      unlimited_session: true,
      templates_required: false,
      cloud_api: false
    }
  }.freeze

  def self.for(provider)
    CAPABILITIES[provider.to_s] || {}
  end

  def self.unlimited_session?(provider)
    self.for(provider)[:unlimited_session] == true
  end
end
