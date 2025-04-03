class RemoveTokensFromUsers < ActiveRecord::Migration[7.0]
  def up
    User.find_each do |user|
      if user.tokens.present?
        user.tokens.delete('wavoip_token')
        user.tokens.delete('groq_token')
        user.save
      end
    end
  end

  def down
    # Não há como restaurar os tokens uma vez que foram removidos
  end
end
