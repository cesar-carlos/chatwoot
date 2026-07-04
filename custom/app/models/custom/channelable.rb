# frozen_string_literal: true

module Custom::Channelable
  # Default: channels support agent text replies to contacts.
  # Voice-only channels (e.g. Wavoip) override #supports_outbound_text? to return false.
  def supports_outbound_text?
    true
  end
end
