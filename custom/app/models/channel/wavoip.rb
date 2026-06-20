class Channel::Wavoip < ApplicationRecord
  include Channelable

  self.table_name = 'channel_wavoip'

  EDITABLE_ATTRS = [:phone_number, :device_token, { provider_config: {} }].freeze

  encrypts :device_token if Chatwoot.encryption_configured?

  has_secure_token :webhook_key

  validates :phone_number, presence: true, uniqueness: true

  before_validation :ensure_provider_config_defaults, on: :create

  def name
    'Wavoip'
  end

  def voice_enabled?
    device_token.present? &&
      account.feature_enabled?('channel_voice') &&
      account.feature_enabled?('channel_wavoip')
  end

  def inbound_calls_enabled?
    provider_config['inbound_calls_enabled'] != false
  end

  def webhook_url
    base = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    "#{base}/webhooks/wavoip/#{webhook_key}"
  end

  def webhook_verified?
    provider_config['webhook_verified_at'].present?
  end

  def setup_pending?
    !webhook_verified?
  end

  def regenerate_webhook_key!
    regenerate_webhook_key
    save!
  end

  private

  def ensure_provider_config_defaults
    self.provider_config = (provider_config || {}).reverse_merge('inbound_calls_enabled' => true)
  end
end
