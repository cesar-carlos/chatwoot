# frozen_string_literal: true

class Wavoip::PhoneNormalizer
  # TODO: Phonelib BR-hint treats 10-digit NANP numbers as BR fixed-line; we prefer US when the
  # digit pattern matches NANP. Other international formats without "+" may still mis-parse.
  NANP_PATTERN = /\A[2-9]\d{2}[2-9]\d{6}\z/

  def self.normalize(phone, inbox_phone: nil)
    return if phone.blank?

    raw = phone.to_s.strip
    return raw if raw.start_with?('+')

    digits = raw.gsub(/\D/, '')
    country = country_hint(inbox_phone)

    parse_with_country(phone, country, digits) ||
      parse_international(digits) ||
      "+#{digits}"
  end

  def self.country_hint(inbox_phone)
    return if inbox_phone.blank?

    Phonelib.parse(inbox_phone.to_s).country
  end

  def self.parse_with_country(phone, country, digits)
    parsed_us = parse_as_us_when_nanp_on_brazilian_inbox(phone, country, digits)
    return parsed_us if parsed_us

    parsed = Phonelib.parse(phone, country)
    parsed.e164 if parsed.valid?
  end
  private_class_method :parse_with_country

  def self.parse_international(digits)
    parsed = Phonelib.parse("+#{digits}")
    parsed.e164 if parsed.valid?
  end
  private_class_method :parse_international

  def self.parse_as_us_when_nanp_on_brazilian_inbox(phone, country, digits)
    return unless country == 'BR' && digits.match?(NANP_PATTERN)

    parsed_us = Phonelib.parse(phone, 'US')
    parsed_us.e164 if parsed_us.valid? && parsed_us.country == 'US'
  end
  private_class_method :parse_as_us_when_nanp_on_brazilian_inbox
end
