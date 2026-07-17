# frozen_string_literal: true

# Canonical device statuses used across panel, SDK gates, and QR flows.
# Wavoip sometimes emits human aliases (connected/disconnected).
module Wavoip::DeviceStatusNormalizer
  ALIASES = {
    'connected' => 'open',
    'disconnected' => 'close'
  }.freeze

  module_function

  def normalize(status)
    return status if status.blank?

    key = status.to_s
    ALIASES[key] || ALIASES[key.downcase] || status
  end
end
