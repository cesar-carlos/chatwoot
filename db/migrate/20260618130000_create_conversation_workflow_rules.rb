# FORK: conversation workflow rules
class CreateConversationWorkflowRules < ActiveRecord::Migration[7.1]
  def change
    create_rules_table
  end

  private

  def create_rules_table # rubocop:disable Metrics/MethodLength
    create_table :conversation_workflow_rules do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.integer :trigger_type, null: false, default: 0
      t.integer :duration_minutes, null: false
      t.jsonb :inbox_ids
      t.boolean :ignore_waiting, null: false, default: false
      t.boolean :resolve_on_match, null: false, default: false
      t.text :message
      t.jsonb :conditions, null: false, default: []
      t.jsonb :actions, null: false, default: []
      t.jsonb :options, null: false, default: {}

      t.timestamps
    end

    add_index :conversation_workflow_rules, %i[account_id active position],
              name: 'index_cwr_on_account_active_position'
    add_index :conversation_workflow_rules, %i[account_id trigger_type],
              name: 'index_cwr_on_account_trigger_type'
  end
end
