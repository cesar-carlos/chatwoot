class AddGroqTokenToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :groq_token, :string, default: '', null: false
    add_index :users, :groq_token
  end
end
