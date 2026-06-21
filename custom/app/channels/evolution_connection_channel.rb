# frozen_string_literal: true

class EvolutionConnectionChannel < ApplicationCable::Channel
  def subscribed
    inbox = current_account.inboxes.find(params[:inbox_id])
    channel = inbox.channel
    unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'
      reject
      return
    end

    stream_from "evolution:connection:#{inbox.id}"
  end

  private

  def current_user
    @current_user ||= User.find_by!(pubsub_token: params[:pubsub_token], id: params[:user_id])
  end

  def current_account
    @current_account ||= current_user.accounts.find(params[:account_id])
  end
end
