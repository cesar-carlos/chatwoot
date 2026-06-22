# FORK: persistent audit trail for message attachment retention purges
class ForkCreateAttachmentRetentionEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :attachment_retention_events do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :attachment_id, null: false
      t.bigint :message_id
      t.string :blob_key
      t.bigint :byte_size, default: 0, null: false
      t.datetime :attachment_created_at
      t.string :status, null: false
      t.text :error_message
      t.string :run_id, null: false

      t.timestamps
    end

    add_index :attachment_retention_events, %i[account_id created_at],
              name: 'index_attachment_retention_events_on_account_id_and_created_at'
    add_index :attachment_retention_events, :attachment_id,
              name: 'index_attachment_retention_events_on_attachment_id'
    add_index :attachment_retention_events, :run_id,
              name: 'index_attachment_retention_events_on_run_id'
  end
end
