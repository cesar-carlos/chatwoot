# frozen_string_literal: true

module Custom::Whatsapp::Evolution::EventNames
  module_function

  # Evolution v2.3+ webhooks use dotted lowercase (e.g. messages.upsert);
  # fork handlers expect SCREAMING_SNAKE (MESSAGES_UPSERT).
  def normalize(event)
    event.to_s.tr('.', '_').upcase
  end
end
