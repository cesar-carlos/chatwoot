class Channel::Wavoip < ApplicationRecord
  include Channelable

  self.table_name = 'channel_wavoip'

  EDITABLE_ATTRS = [:phone_number, :device_token, { provider_config: {} }].freeze

  encrypts :device_token if Chatwoot.encryption_configured?

  has_secure_token :webhook_key

  validates :phone_number, presence: true, uniqueness: { scope: :account_id }
  validates :ring_timeout_seconds_value, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 300,
    allow_nil: true
  }
  validate :administrators_toggle_consistent_with_offline_fallback

  before_validation :ensure_provider_config_defaults

  def name
    'Wavoip'
  end

  def voice_enabled?
    device_token.present? &&
      account.feature_enabled?('channel_voice') &&
      account.feature_enabled?('channel_wavoip')
  end

  # Voice-only channel — agents may call but cannot send text to the contact.
  def supports_outbound_text?
    false
  end

  def inbound_calls_enabled?
    provider_config['inbound_calls_enabled'] != false
  end

  def call_recording_enabled?
    provider_config['call_recording_enabled'] != false
  end

  def incoming_call_include_administrators?
    provider_config['incoming_call_include_administrators'] != false
  end

  def incoming_call_offline_fallback
    fallback = provider_config['incoming_call_offline_fallback'].to_s
    return fallback if Wavoip::Calls::IncomingCallRecipients::OFFLINE_FALLBACKS.include?(fallback)

    'assignee_or_inbox_members_and_administrators'
  end

  def incoming_call_notify_busy_agents?
    provider_config['incoming_call_notify_busy_agents'] == true
  end

  def ring_timeout_seconds
    provider_config['ring_timeout_seconds'].to_i
  end

  def ring_timeout_seconds_value
    provider_config['ring_timeout_seconds']&.to_i
  end

  # Outbound calls have no fixed "ring timeout" concept (the agent decides when to give
  # up), so the stale-call safety net uses a much longer, separately configurable ceiling
  # than inbound. Default 15 minutes — long enough to never interrupt a real conversation
  # that simply hasn't reached ACTIVE yet, short enough to eventually clear a call whose
  # ENDED webhook never arrived.
  def outbound_stale_timeout_seconds
    configured = provider_config['outbound_stale_timeout_seconds'].to_i
    configured.positive? ? configured : 900
  end

  def webhook_url
    base = ENV['FRONTEND_URL'].presence
    return nil if base.blank?

    "#{base}/webhooks/wavoip/#{webhook_key}"
  end

  def webhook_verified?
    provider_config['webhook_verified_at'].present?
  end

  def mark_webhook_verified!
    return if webhook_verified?

    with_lock do
      reload
      unless webhook_verified?
        config = (provider_config || {}).dup
        config['webhook_verified_at'] = Time.current.iso8601
        update!(provider_config: config)
      end
    end
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
    self.provider_config = (provider_config || {}).reverse_merge(
      'inbound_calls_enabled' => true,
      'call_recording_enabled' => true
    )
  end

  def administrators_toggle_consistent_with_offline_fallback
    return unless provider_config['incoming_call_offline_fallback'] == 'none'
    return unless provider_config['incoming_call_include_administrators'] == true

    errors.add(:provider_config, 'cannot include administrators when offline fallback is none')
  end
end
