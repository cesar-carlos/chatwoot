# frozen_string_literal: true

# Atomic JSONB merge for provider_config — avoids lost-update races when
# multiple writers (webhooks, import, connection events, settings UI) update
# different keys concurrently.
class Custom::Whatsapp::EvolutionGo::ProviderConfigMerger
  def self.merge!(channel, attrs)
    new(channel).merge!(attrs)
  end

  def initialize(channel)
    @channel = channel
  end

  def merge!(attrs)
    attrs = attrs.stringify_keys
    return @channel.provider_config if attrs.blank?

    Channel::Whatsapp.where(id: @channel.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      [
        "provider_config = COALESCE(provider_config, '{}'::jsonb) || ?::jsonb, updated_at = ?",
        attrs.to_json,
        Time.current
      ]
    )
    @channel.reload.provider_config
  end
end
