# FORK: lightweight skip log for conversation workflow send_message_to_contact
class CreateConversationWorkflowRuleSkips < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_workflow_rule_skips do |t|
      t.references :conversation_workflow_rule, null: false, foreign_key: true,
                                                index: { name: 'index_cwrs_on_rule_id' }
      t.string :action_name, null: false
      t.string :reason, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :conversation_workflow_rule_skips,
              %i[conversation_workflow_rule_id created_at],
              order: { created_at: :desc },
              name: 'index_cwrs_on_rule_id_and_created_at'
  end
end
