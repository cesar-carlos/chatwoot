# frozen_string_literal: true

class Wavoip::Calls::IncomingCallRecipients
  OFFLINE_FALLBACKS = %w[
    none
    assignee
    assignee_or_team_members
    assignee_or_inbox_members
    assignee_or_inbox_members_and_administrators
  ].freeze

  OFFLINE_FALLBACK_RESOLVERS = {
    'none' => :none_scope,
    'assignee' => :assignee_only_scope,
    'assignee_or_team_members' => :assignee_with_team_fallback,
    'assignee_or_inbox_members' => :assignee_with_inbox_fallback,
    'assignee_or_inbox_members_and_administrators' => :assignee_with_broad_fallback
  }.freeze

  def initialize(inbox:, conversation:)
    @inbox = inbox
    @conversation = conversation
    @channel = inbox.channel
  end

  def users
    online = online_member_users
    return online if online.exists?

    if channel.incoming_call_notify_busy_agents?
      busy = busy_agents
      return busy if busy.exists?
    end

    offline_recipients
  end

  def pubsub_tokens
    users.pluck(:pubsub_token).compact
  end

  def escalated_users
    return User.none if offline_fallback == 'none'

    if channel.incoming_call_notify_busy_agents?
      busy = busy_agents
      return busy if busy.exists?
    end

    broad_fallback_scope
  end

  def escalated_pubsub_tokens
    escalated_users.pluck(:pubsub_token).compact
  end

  private

  attr_reader :inbox, :conversation, :channel

  # Unified scope of everyone eligible to receive call notifications.
  # When `incoming_call_include_administrators` is enabled, account admins are
  # included from the very first ring — not only as an offline fallback.
  def recipients_base_scope
    user_ids = inbox.member_ids.dup
    user_ids |= channel.account.administrators.ids if channel.incoming_call_include_administrators?
    User.where(id: user_ids)
  end

  def online_member_users
    online_ids = OnlineStatusTracker.get_available_users(inbox.account_id)
                                    .select { |_key, value| value == 'online' }
                                    .keys
                                    .map(&:to_i)
    recipients_base_scope.where(id: online_ids)
  end

  def offline_recipients
    resolver = OFFLINE_FALLBACK_RESOLVERS.fetch(offline_fallback, :assignee_with_broad_fallback)
    send(resolver)
  end

  def none_scope
    User.none
  end

  def assignee_only_scope
    assignee_scope
  end

  def assignee_with_inbox_fallback
    assignee_or_fallback(inbox_member_scope)
  end

  def assignee_with_team_fallback
    assignee_or_fallback(team_scope)
  end

  def assignee_with_broad_fallback
    assignee_or_fallback(broad_fallback_scope)
  end

  def assignee_or_fallback(fallback_scope)
    scope = assignee_scope
    scope.exists? ? scope : fallback_scope
  end

  def assignee_scope
    assignee = conversation&.assignee
    return User.none if assignee.blank?

    User.where(id: assignee.id)
  end

  def team_scope
    team = conversation&.team
    return User.none if team.blank?

    User.where(id: team.member_ids)
  end

  def inbox_member_scope
    User.where(id: inbox.member_ids)
  end

  def busy_agents
    busy_ids = OnlineStatusTracker.get_available_users(inbox.account_id)
                                  .select { |_key, value| value == 'busy' }
                                  .keys
                                  .map(&:to_i)
    recipients_base_scope.where(id: busy_ids)
  end

  def broad_fallback_scope
    recipients_base_scope
  end

  def offline_fallback
    channel.incoming_call_offline_fallback
  end
end
