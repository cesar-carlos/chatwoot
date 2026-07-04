# frozen_string_literal: true

module Custom::Api::V1::Accounts::ConversationsControllerEvolutionGo
  def update_last_seen
    super
    mark_evolution_go_messages_read
  end

  private

  def mark_evolution_go_messages_read
    return if @conversation.blank?

    Custom::Whatsapp::EvolutionGo::MarkReadService.new(conversation: @conversation).perform
  end
end

Api::V1::Accounts::ConversationsController.prepend(Custom::Api::V1::Accounts::ConversationsControllerEvolutionGo)
