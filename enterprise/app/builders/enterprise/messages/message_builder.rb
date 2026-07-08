module Enterprise::Messages::MessageBuilder
  private

  def message_type
    return @message_type if @params[:content_type] == 'voice_call'

    super
  end
end
