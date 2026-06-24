# frozen_string_literal: true

class Wavoip::PhoneNormalizer
  def self.normalize(phone, inbox_phone: nil)
    return if phone.blank?

    raw = phone.to_s.strip
    return raw if raw.start_with?('+')

    digits = raw.gsub(/\D/, '')
    return "+#{digits}" unless brazilian_inbox?(inbox_phone)

    if digits.match?(/\A\d{10,11}\z/)
      "+55#{digits}"
    else
      "+#{digits}"
    end
  end

  def self.brazilian_inbox?(inbox_phone)
    inbox_phone.to_s.gsub(/\D/, '').start_with?('55')
  end
end
