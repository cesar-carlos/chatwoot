class AddGroqTokenToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :groq_token, :string unless column_exists?(:users, :groq_token)
  end
end
