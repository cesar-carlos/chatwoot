# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::FieldDig
  module_function

  def dig_field(hash, *keys)
    return nil if hash.blank?

    keys.lazy.map { |key| dig_value(hash, key) }.find { |value| !value.nil? }
  end

  def dig_value(hash, key)
    variants = [key, key.to_s.camelize(:lower), key.to_s.camelize]
    variants.each do |variant|
      return hash[variant] if hash.key?(variant)
      return hash[variant.to_s] if hash.key?(variant.to_s)
    end
    nil
  end
end
