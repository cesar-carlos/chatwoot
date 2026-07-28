module Custom::Messages::MessageBuilder
  # FORK: share contact card + attachment_ids clone for forward — keep #perform in sync with upstream on merge
  def perform
    assert_wavoip_public_reply_allowed!
    merge_cloned_attachment_blobs!

    @message = @conversation.messages.build(message_params)
    attach_shared_contact_from_crm
    process_attachments
    process_emails
    process_email_content
    @message.save!
    @message
  end

  private

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

  # FORK: pseudo-forward — clone source attachments by id (avoids browser CORS fetch)
  def merge_cloned_attachment_blobs!
    ids = attachment_ids_from_params
    return if ids.blank?

    blobs = Custom::Messages::AttachmentCloneService.new(
      account: @account,
      attachment_ids: ids
    ).perform
    @attachments = Array.wrap(@attachments) + blobs
  end

  def attachment_ids_from_params
    raw = @params[:attachment_ids] || @params['attachment_ids']
    Array.wrap(raw).compact_blank
  end
end

Messages::MessageBuilder.prepend(Custom::Messages::MessageBuilder)
