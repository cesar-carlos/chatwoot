# frozen_string_literal: true

class Custom::Whatsapp::Evolution::Broadcaster
  pattr_initialize [:inbox!]

  def broadcast_disconnected
    payload = {
      event: 'evolution.connection_closed',
      data: {
        account_id: inbox.account_id,
        inbox_id: inbox.id,
        inbox_name: inbox.name
      }
    }

    member_tokens.each { |token| ActionCable.server.broadcast(token, payload) }
  end

  private

  def member_tokens
    user_ids = inbox.members.ids | inbox.account.administrators.ids
    User.where(id: user_ids).pluck(:pubsub_token).compact
  end
end
