module Custom::Messages::MessageBuilder
  # FORK: share contact card — keep #perform in sync with upstream Messages::MessageBuilder on merge
  def perform
    @message = @conversation.messages.build(message_params)
    attach_shared_contact_from_crm
    process_attachments
    process_emails
    process_email_content
    @message.save!
    @message
  end

  private

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
