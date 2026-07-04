# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::FieldDig
  module_function

  def dig_field(hash, *keys)
    return nil if hash.blank?

    keys.lazy.map { |key|
      variants = [key, key.to_s.camelize(:lower), key.to_s.camelize]
      variants.map { |k| hash[k] || hash[k.to_s] }.find(&:present?)
    }.find(&:present?)
  end
end
