# frozen_string_literal: true

class Wavoip::PhoneNormalizer
  NANP_PATTERN = /\A[2-9]\d{2}[2-9]\d{6}\z/

  # Longest-prefix first so e.g. 593 (EC) wins over 59 if both were listed.
  LATAM_COUNTRY_PREFIXES = {
    '593' => 'EC', '598' => 'UY', '595' => 'PY', '591' => 'BO',
    '503' => 'SV', '502' => 'GT', '507' => 'PA', '506' => 'CR',
    '505' => 'NI', '504' => 'HN', '58' => 'VE', '57' => 'CO',
    '56' => 'CL', '55' => 'BR', '54' => 'AR', '53' => 'CU',
    '52' => 'MX', '51' => 'PE'
  }.sort_by { |prefix, _| -prefix.length }.freeze

  def self.normalize(phone, inbox_phone: nil)
    return if phone.blank?

    raw = phone.to_s.strip
    return raw if raw.start_with?('+')

    digits = raw.gsub(/\D/, '')
    country = country_hint(inbox_phone)

    parse_with_country(phone, country, digits) ||
      infer_country_from_digits(digits) ||
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

    return unless country

    parsed = Phonelib.parse(phone, country)
    return parsed.e164 if parsed.valid?

    # Local national numbers often arrive as digits-only; retry with the
    # inbox country so LATAM mobiles without a leading country code resolve.
    parsed_digits = Phonelib.parse(digits, country)
    parsed_digits.e164 if parsed_digits.valid?
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

  def self.infer_country_from_digits(digits)
    return if digits.blank?

    LATAM_COUNTRY_PREFIXES.each do |prefix, country|
      next unless digits.start_with?(prefix)

      parsed = Phonelib.parse("+#{digits}", country)
      return parsed.e164 if parsed.valid?
    end

    nil
  end
  private_class_method :infer_country_from_digits
end
