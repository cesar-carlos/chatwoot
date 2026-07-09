# FORK: partial indexes for pending_stale and unassigned_too_long workflow scopes
class AddConversationWorkflowExtendedTriggerIndexes < ActiveRecord::Migration[7.1]
  def change
    # pending_stale: status = pending (2), ordered by last_activity_at
    add_index :conversations, %i[account_id last_activity_at],
              name: 'index_conv_workflow_pending_stale',
              where: 'status = 2'

    # unassigned_too_long: open + unassigned, ordered by created_at
    add_index :conversations, %i[account_id created_at],
              name: 'index_conv_workflow_unassigned',
              where: 'status = 0 AND assignee_id IS NULL'
  end
end
