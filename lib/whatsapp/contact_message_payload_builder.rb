class Whatsapp::ContactMessagePayloadBuilder
  def self.build(attachment)
    meta = attachment.meta || {}
    first_name = meta['firstName'] || meta['first_name']
    last_name = meta['lastName'] || meta['last_name']
    phone = attachment.fallback_title
    company = meta['companyName'] || meta['company_name']

    payload = {
      name: {
        formatted_name: [first_name, last_name].compact.join(' ').presence || phone,
        first_name: first_name,
        last_name: last_name
      }.compact,
      phones: [{ phone: phone, type: 'CELL' }]
    }
    # FORK: share contact card
    payload[:org] = { company: company } if company.present?

    payload
  end
end
