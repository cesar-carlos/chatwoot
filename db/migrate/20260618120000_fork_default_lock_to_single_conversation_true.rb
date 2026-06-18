# FORK: default new inboxes to single conversation history mode
class ForkDefaultLockToSingleConversationTrue < ActiveRecord::Migration[7.1]
  def change
    change_column_default :inboxes, :lock_to_single_conversation, from: false, to: true
  end
end
