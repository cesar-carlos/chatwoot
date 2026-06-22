# FORK: track repeated purge failures to quarantine attachments from retention scope
class ForkCreateAttachmentRetentionFailures < ActiveRecord::Migration[7.1]
  def change
    create_table :attachment_retention_failures do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :attachment_id, null: false
      t.integer :failure_count, null: false, default: 0
      t.text :last_error
      t.datetime :last_failed_at

      t.timestamps
    end

    add_index :attachment_retention_failures, :attachment_id,
              unique: true,
              name: 'index_attachment_retention_failures_on_attachment_id'
  end
end
