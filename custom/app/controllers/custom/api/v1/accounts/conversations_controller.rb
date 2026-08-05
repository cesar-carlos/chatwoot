# frozen_string_literal: true

module Custom::Api::V1::Accounts::ConversationsController
  def create
    Current.conversation_opened_by = Custom::Conversations::OpenedByStamper::AGENT
    super
  ensure
    Current.conversation_opened_by = nil
  end

  def toggle_status
    stamp_opened_by_agent_on_reopen!
    super
  end

  def update_last_seen
    super
    mark_evolution_go_messages_read
  end

  private

  def stamp_opened_by_agent_on_reopen!
    return unless Current.user.is_a?(User)
    return unless reopening_conversation_to_open?

    Custom::Conversations::OpenedByStamper.stamp!(
      @conversation,
      Custom::Conversations::OpenedByStamper::AGENT
    )
  end

  def reopening_conversation_to_open?
    if params[:status].present?
      params[:status].to_s == 'open' && !@conversation.open?
    else
      # toggle_status: open ↔ resolved; pending/snoozed → open
      !@conversation.open?
    end
  end

  def mark_evolution_go_messages_read
    return if @conversation.blank?

    Custom::Whatsapp::EvolutionGo::MarkReadService.new(conversation: @conversation).perform
  end
end

Api::V1::Accounts::ConversationsController.prepend_mod_with('Api::V1::Accounts::ConversationsController')
