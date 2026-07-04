class ScopeChannelWavoipPhoneUniquenessToAccount < ActiveRecord::Migration[7.1]
  def change
    remove_index :channel_wavoip, :phone_number
    add_index :channel_wavoip, %i[account_id phone_number], unique: true
  end
end
