# FORK: cascade-delete history migration rows when source/target inboxes are removed
class ForkAddInboxFksToInboxHistoryMigrations < ActiveRecord::Migration[7.1]
  def change
    add_foreign_key :inbox_history_migrations, :inboxes,
                    column: :source_inbox_id, on_delete: :cascade
    add_foreign_key :inbox_history_migrations, :inboxes,
                    column: :target_inbox_id, on_delete: :cascade
    add_foreign_key :inbox_history_migrations, :users,
                    column: :requested_by_id, on_delete: :nullify
  end
end
