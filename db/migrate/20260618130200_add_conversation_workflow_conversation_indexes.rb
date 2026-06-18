# FORK: partial indexes for conversation workflow scheduler queries
class AddConversationWorkflowConversationIndexes < ActiveRecord::Migration[7.1]
  def change
    add_index :conversations, %i[account_id waiting_since],
              name: 'index_conv_workflow_waiting',
              where: 'status = 0 AND waiting_since IS NOT NULL'

    add_index :conversations, %i[account_id last_activity_at],
              name: 'index_conv_workflow_inactivity',
              where: 'status = 0'
  end
end
