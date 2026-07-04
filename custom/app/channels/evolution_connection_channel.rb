# frozen_string_literal: true

class EvolutionConnectionChannel < ApplicationCable::Channel
  def subscribed
    inbox = current_account.inboxes.find(params[:inbox_id])
    channel = inbox.channel
    unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'
      reject
      return
    end

    unless inbox_accessible?(inbox)
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

  # Connection status/QR/pairing code is sensitive (it can be used to pair a
  # new phone as the account's WhatsApp) — restrict it to administrators,
  # matching the REST `evolution_connection`/`evolution_reconnect`/
  # `evolution_logout`/`evolution_restart` actions (all `:update?`, i.e.
  # admin-only). A merely-assigned, non-admin agent must not be able to
  # subscribe to this stream even if they can see the inbox elsewhere.
  def inbox_accessible?(inbox)
    inbox.account.administrators.exists?(id: current_user.id)
  end
end
