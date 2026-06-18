module Whatsapp::ContactDelivery
  private

  def contact_attachment?(message)
    message.attachments.one? && message.attachments.first.contact?
  end

  def build_contact_entry(attachment)
    Whatsapp::ContactMessagePayloadBuilder.build(attachment)
  end

  # FORK: share contact card
  def send_contact_message(phone_number, message)
    attachment = message.attachments.first
    response = HTTParty.post(
      contact_messages_url,
      headers: api_headers,
      body: contact_message_body(phone_number, message, attachment).to_json
    )

    process_response(response, message)
  end

  def contact_message_body(phone_number, message, attachment)
    raise NotImplementedError
  end
end
