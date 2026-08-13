# frozen_string_literal: true

# Dashboard agent compose: find-or-start a conversation with ownership rules.
# Does not replace Conversations::Resolver for inbound channel traffic.
class Custom::Conversations::AgentStartService
  pattr_initialize [:contact_inbox!, :user!, :params!]

  def perform
    contact_inbox.with_lock do
      existing = find_conversation
      existing ? prepare_existing!(existing) : create_conversation!
    end
  end

  private

  def inbox
    contact_inbox.inbox
  end

  def find_conversation
    explicit = conversation_from_param
    return explicit if explicit.present?

    # Parity with Custom::Conversations::Resolver — Wavoip always reuses latest
    return latest_conversation if wavoip_inbox?

    if inbox.lock_to_single_conversation?
      latest_conversation
    else
      contact_inbox.conversations.where.not(status: :resolved).order(created_at: :desc).first
    end
  end

  def conversation_from_param
    display_id = params[:conversation_id].presence
    return if display_id.blank?

    contact_inbox.conversations.find_by(display_id: display_id)
  end

  def latest_conversation
    contact_inbox.conversations.order(created_at: :desc).first
  end

  def wavoip_inbox?
    inbox.channel.is_a?(Channel::Wavoip)
  end

  def create_conversation!
    ::Conversation.create!(
      Custom::Conversations::OpenedByStamper.merge_create_params(create_params)
    )
  end

  def create_params
    conversation_params.merge(assignee_id: user.id)
  end

  def prepare_existing!(conversation)
    if conversation.resolved? || conversation.snoozed?
      reopen_and_assign!(conversation)
    elsif conversation.open? || conversation.pending?
      prepare_active!(conversation)
    else
      conversation
    end
  end

  def reopen_and_assign!(conversation)
    Custom::Conversations::OpenedByStamper.stamp!(
      conversation,
      Custom::Conversations::OpenedByStamper::AGENT
    )
    conversation.open!
    assign_to_initiator!(conversation)
    conversation
  end

  def prepare_active!(conversation)
    raise CustomExceptions::Conversation::OpenAssignedToOtherAgent.new({}) if conversation.assignee_id.present? && conversation.assignee_id != user.id

    raise CustomExceptions::Conversation::OutsidePermissionScope.new({}) unless conversation_visible?(conversation)

    if conversation.pending?
      Custom::Conversations::OpenedByStamper.stamp!(
        conversation,
        Custom::Conversations::OpenedByStamper::AGENT
      )
      conversation.open!
    end

    # Force initiator even if open! auto-assigned another agent (reply_assigned_only).
    assign_to_initiator!(conversation)
    conversation
  end

  def assign_to_initiator!(conversation)
    conversation.update!(assignee_id: user.id) if conversation.assignee_id != user.id
  end

  def conversation_visible?(conversation)
    ConversationPolicy.new(policy_user_context, conversation).show?
  end

  def policy_user_context
    {
      user: user,
      account: inbox.account,
      account_user: AccountUser.find_by(user: user, account_id: inbox.account_id)
    }
  end

  # rubocop:disable Metrics/AbcSize -- mirrors ConversationBuilder create attrs
  def conversation_params
    additional_attributes = params[:additional_attributes]&.permit! || {}
    custom_attributes = params[:custom_attributes]&.permit! || {}
    status = params[:status].present? ? { status: params[:status] } : {}

    {
      account_id: inbox.account_id,
      inbox_id: contact_inbox.inbox_id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      additional_attributes: additional_attributes,
      custom_attributes: custom_attributes,
      snoozed_until: params[:snoozed_until],
      assignee_id: params[:assignee_id],
      team_id: params[:team_id]
    }.merge(status)
  end
  # rubocop:enable Metrics/AbcSize
end
