# frozen_string_literal: true

module Custom::AutomationRule
  def conditions_attributes
    super + %w[opened_by]
  end
end
