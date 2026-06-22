# FORK: speed up message attachment retention purge queries
class ForkAddIndexAttachmentsOnAccountIdAndCreatedAt < ActiveRecord::Migration[7.1]
  def change
    add_index :attachments, %i[account_id created_at],
              name: 'index_attachments_on_account_id_and_created_at',
              if_not_exists: true
  end
end
