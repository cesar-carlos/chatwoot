# frozen_string_literal: true

# Shared detector for WhatsApp protocol / encrypted envelopes that must not become
# Chatwoot text bubbles (or open conversations / welcome bots).
module Custom::Whatsapp::EvolutionGo::ProtocolNoise
  module_function

  def protocol_only?(data)
    message = message_from(data)
    return false if message.blank?
    return true if secret_encrypted_only?(message)

    protocol_message_only?(message)
  end

  def protocol_message_only?(message)
    message = (message || {}).with_indifferent_access
    substantive_keys = message.keys.map(&:to_s) - %w[messageContextInfo]
    substantive_keys == %w[protocolMessage]
  end

  def secret_encrypted_only?(message)
    message = (message || {}).with_indifferent_access
    return false if message[:secretEncryptedMessage].blank?

    substantive = message.keys.map(&:to_s) - %w[messageContextInfo secretEncryptedMessage]
    substantive.empty?
  end

  def message_from(data)
    return {} if data.blank?

    data = data.with_indifferent_access
    raw = data[:message] || data[:Message] || data
    return {} unless raw.is_a?(Hash)

    Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.unwrap_nested_message(raw)
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- key/message shape variants
  def log_skip!(channel:, data:, reason: 'protocol_noise')
    data = (data || {}).with_indifferent_access
    key = data[:key] || data[:Key] || {}
    key = key.with_indifferent_access if key.is_a?(Hash)
    message = message_from(data)
    protocol = (message[:protocolMessage] || {}).with_indifferent_access
    Rails.logger.info(
      "[EVOLUTION_GO] skipped #{reason} channel=#{channel&.id} " \
      "id=#{key[:id] || key[:ID]} keys=#{message.keys.join(',')} " \
      "protocol_type=#{protocol[:type] || protocol[:typeName]}"
    )
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
end
