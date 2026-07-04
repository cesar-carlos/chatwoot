# frozen_string_literal: true

class EvolutionGoConnectionChannel < ApplicationCable::Channel
  def subscribed
    inbox = current_account.inboxes.find(params[:inbox_id])
    channel = inbox.channel
    unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'
      reject
      return
    end

    unless inbox_accessible?(inbox)
      reject
      return
    end

    stream_from "evolution_go:connection:#{inbox.id}"
  end

  private

  def current_user
    @current_user ||= User.find_by!(pubsub_token: params[:pubsub_token], id: params[:user_id])
  end

  def current_account
    @current_account ||= current_user.accounts.find(params[:account_id])
  end

  def inbox_accessible?(inbox)
    inbox.account.administrators.exists?(id: current_user.id)
  end
end
