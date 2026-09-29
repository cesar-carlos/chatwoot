# frozen_string_literal: true

class Custom::Conversations::EventRecipientService
  MANAGE_ALL_PERMISSION = 'conversation_manage'
  UNASSIGNED_PERMISSION = 'conversation_unassigned_manage'
  TEAM_UNASSIGNED_PERMISSION = 'conversation_team_unassigned_manage'
  PARTICIPATING_PERMISSION = 'conversation_participating_manage'
  CONVERSATION_PERMISSIONS = [
    UNASSIGNED_PERMISSION,
    TEAM_UNASSIGNED_PERMISSION,
    PARTICIPATING_PERMISSION
  ].freeze

  attr_reader :account, :conversation, :tokens

  def initialize(account:, conversation:, tokens:)
    @account = account
    @conversation = conversation
    @tokens = tokens
  end

  def perform
    account_users_by_token = candidate_account_users.index_by { |account_user| account_user.user.pubsub_token }

    tokens.reject do |token|
      account_user = account_users_by_token[token]
      account_user.present? && !allowed?(account_user)
    end
  end

  private

  def candidate_account_users
    @candidate_account_users ||= account.account_users
                                        .agent
                                        .where.not(custom_role_id: nil)
                                        .includes(:custom_role, :user)
                                        .where(users: { pubsub_token: tokens })
                                        .references(:user)
  end

  def allowed?(account_user)
    return false unless inbox_member_user_ids.include?(account_user.user_id)

    conversation_allowed?(account_user.user_id, account_user.custom_role.permissions)
  end

  def conversation_allowed?(user_id, permissions)
    permissions.include?(MANAGE_ALL_PERMISSION) ||
      assigned_to_user_with_conversation_permission?(user_id, permissions) ||
      unassigned_permission?(permissions) ||
      team_unassigned_permission?(user_id, permissions) ||
      participating_permission?(user_id, permissions)
  end

  def assigned_to_user_with_conversation_permission?(user_id, permissions)
    conversation.assignee_id == user_id && permissions.intersect?(CONVERSATION_PERMISSIONS)
  end

  def participating_permission?(user_id, permissions)
    permissions.include?(PARTICIPATING_PERMISSION) && participant_user_ids.include?(user_id)
  end

  def unassigned_permission?(permissions)
    unassigned? && permissions.include?(UNASSIGNED_PERMISSION)
  end

  def team_unassigned_permission?(user_id, permissions)
    unassigned? &&
      permissions.include?(TEAM_UNASSIGNED_PERMISSION) &&
      conversation.team_id.present? &&
      team_member_user_ids.include?(user_id)
  end

  def unassigned?
    conversation.assignee_id.nil? && conversation.assignee_agent_bot_id.nil?
  end

  def inbox_member_user_ids
    @inbox_member_user_ids ||= InboxMember.where(inbox_id: conversation.inbox_id, user_id: candidate_user_ids).pluck(:user_id)
  end

  def participant_user_ids
    @participant_user_ids ||= conversation.conversation_participants.where(user_id: candidate_user_ids).pluck(:user_id)
  end

  def team_member_user_ids
    @team_member_user_ids ||= TeamMember.where(team_id: conversation.team_id, user_id: candidate_user_ids).pluck(:user_id)
  end

  def candidate_user_ids
    @candidate_user_ids ||= candidate_account_users.map(&:user_id)
  end
end
