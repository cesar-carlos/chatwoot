module Custom::Messages::MessageBuilder
  # FORK: share contact card — keep #perform in sync with upstream Messages::MessageBuilder on merge
  def perform
    assert_wavoip_public_reply_allowed!

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
    channel = @conversation.inbox&.channel
    return false unless channel.respond_to?(:supports_outbound_text?)
    return false if channel.supports_outbound_text?
    return false if @private
    return false unless @message_type == 'outgoing'
    return false if @params[:content_type].to_s == 'voice_call'

    true
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
end

Messages::MessageBuilder.prepend(Custom::Messages::MessageBuilder)
