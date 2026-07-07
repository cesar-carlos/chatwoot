# frozen_string_literal: true

class Custom::Whatsapp::Webhooks::EvolutionGoReadReceiptNormalizer
  include Custom::Whatsapp::Webhooks::EvolutionGo::StatusNormalizer

  attr_reader :channel, :envelope

  def initialize(channel, envelope)
    @channel = channel
    @envelope = envelope
  end

  def perform
    envelope_data = envelope.with_indifferent_access
    return unless envelope_data[:event].to_s.upcase.in?(%w[READ_RECEIPT RECEIPT])

    data = Custom::Whatsapp::Webhooks::EvolutionGoReadReceiptPayloadAdapter.canonicalize_data(
      envelope_data[:data],
      envelope_state: envelope_data[:state]
    )
    return if data.blank?

    normalize_read_receipt(data)
  end

  private

  def config
    channel.provider_config || Custom::Whatsapp::EvolutionGo::ProviderConfigDefaults::DEFAULTS
  end
end
