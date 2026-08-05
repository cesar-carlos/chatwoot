# frozen_string_literal: true

class MacroDrop < BaseDrop
  def name
    @obj.try(:name)
  end
end
