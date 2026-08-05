# frozen_string_literal: true

# Exposes {{rule.*}} / {{macro.*}} in Liquid when Current.executed_by is set.
module Custom::Message::LiquidRuleContext
  private

  def message_drops
    drops = super
    executed = Current.executed_by
    case executed
    when AutomationRule
      drops.merge('rule' => AutomationRuleDrop.new(executed))
    when Macro
      drops.merge('macro' => MacroDrop.new(executed))
    else
      drops
    end
  end
end
