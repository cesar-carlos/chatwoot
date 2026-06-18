class Custom::ConversationWorkflow::TemplateMessageSender
  def initialize(conversation:, message:)
    @conversation = conversation
    @message = message
  end

  def perform
    MessageTemplates::Template::AutoResolve.new(conversation: @conversation, message: @message).perform
  end
end
