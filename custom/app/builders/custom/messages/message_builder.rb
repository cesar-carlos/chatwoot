# frozen_string_literal: true

module Custom::Messages::MessageBuilder
  def perform
    assert_reply_assigned_only_allowed!
    assert_wavoip_public_reply_allowed!
    merge_cloned_attachment_blobs!
    super
  end

  private

  def process_attachments
    attach_shared_contact_from_crm
    super
  end

  # FORK: custom role reply assigned only — covers API create, macros, conversation create+message
  def assert_reply_assigned_only_allowed!
    return if @user.blank? || !@user.is_a?(User)

    account_user = AccountUser.find_by(user_id: @user.id, account_id: @conversation.account_id)
    context = { user: @user, account: @conversation.account, account_user: account_user }
    return if ConversationPolicy.new(context, @conversation).reply?

    raise Pundit::NotAuthorizedError, query: :reply?, record: @conversation
  end

  def assert_wavoip_public_reply_allowed!
    return unless wavoip_outgoing_public_message?

    raise CustomExceptions::Wavoip::VoiceOnlyInbox.new({})
  end

  def wavoip_outgoing_public_message?
    Custom::Channels::OutboundText.blocks_outgoing_public_message?(
      channel: @conversation.inbox&.channel,
      private: @private,
      message_type: @message_type,
      content_type: @params[:content_type]
    )
  end

  def attach_shared_contact_from_crm
    Custom::Messages::SharedContactHandler.new(
      account: @account,
      conversation: @conversation,
      params: @params,
      attachments: @attachments,
      user: @user
    ).attach_to(@message)
  end

  # Clone source attachments by id (avoids browser CORS fetch). Requires
  # forwarded_from_message_id so callers cannot clone arbitrary account blobs.
  def merge_cloned_attachment_blobs!
    ids = attachment_ids_from_params
    source_id = forwarded_from_message_id
    return if ids.blank? || source_id.blank?

    blobs = Custom::Messages::AttachmentCloneService.new(
      account: @account,
      attachment_ids: ids,
      source_message_id: source_id
    ).perform
    @attachments = Array.wrap(@attachments) + blobs
  end

  def attachment_ids_from_params
    raw = @params[:attachment_ids] || @params['attachment_ids']
    Array.wrap(raw).compact_blank
  end

  def forwarded_from_message_id
    attrs = content_attributes
    return if attrs.blank?

    attrs[:forwarded_from_message_id].presence || attrs['forwarded_from_message_id'].presence
  end
end
