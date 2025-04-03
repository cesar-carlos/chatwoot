class AddWavoipTokenToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :wavoip_token, :string, default: '', null: false
    add_index :users, :wavoip_token
  end
end
