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
    return unless envelope_data[:event] == 'READ_RECEIPT'

    data = envelope_data[:data]
    return if data.blank?

    normalize_read_receipt(data)
  end

  private

  def phone_from_jid(jid)
    digits = jid.to_s.split('@').first
    return if digits.blank?

    digits.gsub(/\D/, '')
  end
end
