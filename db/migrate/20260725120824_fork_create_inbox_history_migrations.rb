# FORK: track inbox-to-inbox conversation history migrations (WhatsApp A → B)
class ForkCreateInboxHistoryMigrations < ActiveRecord::Migration[7.1]
  def change
    create_table :inbox_history_migrations do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :source_inbox_id, null: false
      t.bigint :target_inbox_id, null: false
      t.bigint :requested_by_id
      t.string :status, null: false, default: 'pending'
      t.jsonb :stats, null: false, default: {}
      t.text :error_message
      t.datetime :started_at
      t.datetime :heartbeat_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :inbox_history_migrations, :source_inbox_id
    add_index :inbox_history_migrations, :target_inbox_id
    add_index :inbox_history_migrations, %i[account_id created_at]
  end
end
