# frozen_string_literal: true

class AutomationRuleDrop < BaseDrop
  def name
    @obj.try(:name)
  end
end
