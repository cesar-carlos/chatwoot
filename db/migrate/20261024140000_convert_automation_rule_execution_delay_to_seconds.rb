class ConvertAutomationRuleExecutionDelayToSeconds < ActiveRecord::Migration[7.1]
  # FORK: existing rows stored minutes. Pending rows keep their absolute due_at.
  def up
    execute 'UPDATE automation_rules SET execution_delay = execution_delay * 60 WHERE execution_delay IS NOT NULL'
  end

  def down
    execute 'UPDATE automation_rules SET execution_delay = execution_delay / 60 WHERE execution_delay IS NOT NULL'
  end
end
