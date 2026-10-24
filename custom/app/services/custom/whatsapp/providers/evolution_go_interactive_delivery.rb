# frozen_string_literal: true

module Custom::Whatsapp::Providers::EvolutionGoInteractiveDelivery
  private

  def structured_content?(message)
    %w[cards article].include?(message.content_type)
  end

  def send_structured_message(phone_number, message)
    if message.content_type == 'cards'
      send_cards_message(phone_number, message)
    else
      send_article_message(phone_number, message)
    end
  end

  def send_cards_message(phone_number, message)
    result = Custom::Whatsapp::EvolutionGo::InteractivePayload.carousel(message)
    return fail_interactive_payload!(message, result.error) unless result.success?

    response = api_client.send_carousel(
      number: phone_number,
      cards: result.payload[:cards],
      body: interactive_body_text(message),
      quoted: build_quoted_context(phone_number, message),
      delay: outbound_delay,
      **delivery_options(phone_number, message)
    )
    message_id = process_response(response, message)
    mark_incoming_read_after_reply(phone_number, message) if message_id.present?
    message_id
  end

  def send_article_message(phone_number, message)
    result = Custom::Whatsapp::EvolutionGo::InteractivePayload.links(message)
    return fail_interactive_payload!(message, result.error) unless result.success?

    message_id = deliver_article_links(phone_number, message, result.payload)
    mark_incoming_read_after_reply(phone_number, message) if message_id.present?
    message_id
  end

  def deliver_article_links(phone_number, message, links)
    message_id = nil
    intro = interactive_body_text(message)
    quoted = build_quoted_context(phone_number, message)
    base = delivery_options(phone_number, message).merge(delay: outbound_delay)

    links.each_with_index do |link, index|
      options = base.dup
      if index.zero?
        options[:text] = intro if intro.present?
        options[:quoted] = quoted if quoted.present?
      end
      response = api_client.send_link(number: phone_number, **link, **options)
      message_id = process_attachment_response(response, message, index, message_id)
      return nil if message_id == :failed
    end

    message_id
  end

  def interactive_body_text(message)
    return if message.content.blank?

    apply_outbound_text(message.outgoing_content, message)
  end

  def fail_interactive_payload!(message, error_text)
    message.external_error = error_text
    message.status = :failed
    message.save!
    nil
  end
end
