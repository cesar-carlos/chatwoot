# FORK: preserve audit events when an account is deleted
class ForkNullifyAccountOnAttachmentRetentionEvents < ActiveRecord::Migration[7.1]
  def up
    remove_foreign_key :attachment_retention_events, :accounts
    change_column_null :attachment_retention_events, :account_id, true
    add_foreign_key :attachment_retention_events, :accounts, on_delete: :nullify
  end

  def down
    remove_foreign_key :attachment_retention_events, :accounts
    change_column_null :attachment_retention_events, :account_id, false
    add_foreign_key :attachment_retention_events, :accounts
  end
end
