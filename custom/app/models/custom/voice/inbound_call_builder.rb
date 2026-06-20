# frozen_string_literal: true

module Custom::Voice::InboundCallBuilder
  private

  def source_id_for_provider
    return from_number.to_s.delete_prefix('+') if provider == :wavoip

    super
  end
end

Voice::InboundCallBuilder.prepend_mod_with('Voice::InboundCallBuilder')
