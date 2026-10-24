# frozen_string_literal: true

module Custom::Whatsapp::Webhooks::EvolutionGo::InteractiveInboundText
  include Custom::Whatsapp::Webhooks::EvolutionGo::CarouselInboundText
  include Custom::Whatsapp::Webhooks::EvolutionGo::PollInboundText

  LIST_PLACEHOLDER = '[List message]'
  BUTTONS_PLACEHOLDER = '[Button message]'

  private

  def interactive_inbound_body(message)
    message = (message || {}).with_indifferent_access
    list_inbound_text(message) ||
      buttons_inbound_text(message) ||
      carousel_inbound_text(message) ||
      poll_creation_text(message) ||
      poll_vote_text_from_message(message)
  end

  def list_inbound_text(message)
    list = inbound_field_dig.dig_field(message, 'listMessage')
    return unless list.is_a?(Hash)

    list = list.with_indifferent_access
    title = inbound_field_dig.dig_field(list, 'title').to_s.presence
    description = inbound_field_dig.dig_field(list, 'description').to_s.presence
    rows = list_row_titles(list).map { |row| "- #{row}" }
    [title, description, *rows].compact.join("\n\n").presence || LIST_PLACEHOLDER
  end

  def list_row_titles(list)
    sections = inbound_field_dig.dig_field(list, 'sections')
    Array.wrap(sections).flat_map do |section|
      next [] unless section.is_a?(Hash)

      rows = inbound_field_dig.dig_field(section.with_indifferent_access, 'rows')
      Array.wrap(rows).filter_map do |row|
        next unless row.is_a?(Hash)

        inbound_field_dig.dig_field(row.with_indifferent_access, 'title').to_s.presence
      end
    end
  end

  def buttons_inbound_text(message)
    buttons = inbound_field_dig.dig_field(message, 'buttonsMessage')
    return unless buttons.is_a?(Hash)

    buttons = buttons.with_indifferent_access
    body = inbound_field_dig.dig_field(buttons, 'contentText').to_s.presence ||
           inbound_field_dig.dig_field(buttons, 'text').to_s.presence
    labels = inbound_button_labels(inbound_field_dig.dig_field(buttons, 'buttons'))
    parts = [body, *labels.map { |label| "[#{label}]" }].compact
    parts.join("\n\n").presence || BUTTONS_PLACEHOLDER
  end

  def inbound_button_labels(buttons)
    Array.wrap(buttons).filter_map { |button| inbound_button_label(button) }.uniq
  end

  def inbound_button_label(button)
    return unless button.is_a?(Hash)

    button = button.with_indifferent_access
    nested = inbound_field_dig.dig_field(button, 'buttonText')
    if nested.is_a?(Hash)
      text = inbound_field_dig.dig_field(nested.with_indifferent_access, 'displayText').to_s.presence
      return text if text
    end

    inbound_field_dig.dig_field(button, 'displayText').to_s.presence ||
      inbound_field_dig.dig_field(button, 'text').to_s.presence ||
      inbound_field_dig.dig_field(button, 'name').to_s.presence
  end

  def inbound_field_dig
    Custom::Whatsapp::EvolutionGo::FieldDig
  end
end
