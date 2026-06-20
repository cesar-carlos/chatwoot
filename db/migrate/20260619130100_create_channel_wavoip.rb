class CreateChannelWavoip < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_wavoip do |t|
      t.string :phone_number, null: false
      t.integer :account_id, null: false
      t.string :device_token
      t.string :webhook_key, null: false
      t.jsonb :provider_config, default: {}

      t.timestamps
    end

    add_index :channel_wavoip, :phone_number, unique: true
    add_index :channel_wavoip, :webhook_key, unique: true
    add_index :channel_wavoip, :account_id
  end
end
