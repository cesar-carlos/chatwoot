# frozen_string_literal: true

module Custom::Whatsapp::Webhooks::EvolutionGo::CarouselInboundText
  CAROUSEL_PLACEHOLDER = '[Carousel]'

  private

  def carousel_inbound_text(message)
    carousel = carousel_node(message)
    return unless carousel.is_a?(Hash)

    carousel = carousel.with_indifferent_access
    cards = Array.wrap(inbound_field_dig.dig_field(carousel, 'cards')).filter_map { |card| carousel_card_text(card) }
    [carousel_intro(message), *cards].compact.join("\n\n").presence || CAROUSEL_PLACEHOLDER
  end

  def carousel_node(message)
    direct = inbound_field_dig.dig_field(message, 'carouselMessage')
    return direct if direct.is_a?(Hash)

    interactive = inbound_field_dig.dig_field(message, 'interactiveMessage')
    return unless interactive.is_a?(Hash)

    inbound_field_dig.dig_field(interactive.with_indifferent_access, 'carouselMessage')
  end

  def carousel_intro(message)
    interactive = inbound_field_dig.dig_field(message, 'interactiveMessage')
    return unless interactive.is_a?(Hash)

    body = inbound_field_dig.dig_field(interactive.with_indifferent_access, 'body')
    return unless body.is_a?(Hash)

    inbound_field_dig.dig_field(body.with_indifferent_access, 'text').to_s.presence
  end

  def carousel_card_text(card)
    return unless card.is_a?(Hash)

    card = card.with_indifferent_access
    labels = carousel_card_button_labels(card).map { |label| "[#{label}]" }
    [carousel_card_title(card), carousel_card_description(card), *labels].compact.join("\n").presence
  end

  def carousel_card_title(card)
    header = inbound_field_dig.dig_field(card, 'header')
    return unless header.is_a?(Hash)

    inbound_field_dig.dig_field(header.with_indifferent_access, 'title').to_s.presence
  end

  def carousel_card_description(card)
    body = inbound_field_dig.dig_field(card, 'body')
    return body.to_s.presence unless body.is_a?(Hash)

    inbound_field_dig.dig_field(body.with_indifferent_access, 'text').to_s.presence
  end

  def carousel_card_button_labels(card)
    labels = inbound_button_labels(inbound_field_dig.dig_field(card, 'buttons'))
    return labels if labels.present?

    native = inbound_field_dig.dig_field(card, 'nativeFlowMessage')
    return [] unless native.is_a?(Hash)

    inbound_button_labels(inbound_field_dig.dig_field(native.with_indifferent_access, 'buttons'))
  end
end
