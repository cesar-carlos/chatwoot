# FORK: drop the unused conversations.current_session_opened_at column.
# It landed in schema.rb from an unrelated schema dump and has no readers or writers.
# Service session reports compute cycle start from reporting events instead.
class RemoveUnusedCurrentSessionOpenedAtFromConversations < ActiveRecord::Migration[7.2]
  def up
    remove_index :conversations,
                 name: 'index_conversations_on_current_session_opened_at',
                 if_exists: true
    remove_column :conversations, :current_session_opened_at, :datetime, if_exists: true
  end

  def down
    add_column :conversations, :current_session_opened_at, :datetime, if_not_exists: true
    add_index :conversations, :current_session_opened_at,
              name: 'index_conversations_on_current_session_opened_at',
              if_not_exists: true
  end
end
