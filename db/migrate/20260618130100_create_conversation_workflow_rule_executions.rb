# FORK: conversation workflow rule dedup executions
class CreateConversationWorkflowRuleExecutions < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_workflow_rule_executions do |t|
      t.references :conversation_workflow_rule, null: false, foreign_key: true, index: { name: 'index_cwre_on_rule_id' }
      t.references :conversation, null: false, foreign_key: true, index: { name: 'index_cwre_on_conversation_id' }
      t.bigint :waiting_since_epoch
      t.bigint :last_activity_epoch
      t.datetime :executed_at, null: false

      t.timestamps
    end

    add_index :conversation_workflow_rule_executions,
              %i[conversation_workflow_rule_id conversation_id waiting_since_epoch],
              unique: true,
              name: 'index_cwre_dedup_waiting_since',
              where: 'waiting_since_epoch IS NOT NULL'

    add_index :conversation_workflow_rule_executions,
              %i[conversation_workflow_rule_id conversation_id last_activity_epoch],
              unique: true,
              name: 'index_cwre_dedup_last_activity',
              where: 'last_activity_epoch IS NOT NULL'
  end
end
