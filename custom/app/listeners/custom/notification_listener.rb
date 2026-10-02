module Custom::NotificationListener
  AGENT_ASSIGNMENT_ATTRIBUTES = %w[assignee_id assignee_agent_bot_id ai_assignee_type].freeze

  def team_changed(event)
    change = event.data[:changed_attributes]&.with_indifferent_access&.[](:team_id)
    return if change && change.last != event.data[:conversation].reload.team_id

    notify_unassigned_team(event)
  end

  def assignee_changed(event)
    super
    changes = (event.data[:changed_attributes] || {}).with_indifferent_access
    # A simultaneous team change owns this transition, avoiding duplicate notices.
    return if changes.key?('team_id')

    removed = changes.slice(*AGENT_ASSIGNMENT_ATTRIBUTES).values.any? { |previous, current| previous.present? && current.nil? }
    return unless removed

    notify_unassigned_team(event)
  end

  private

  def notify_unassigned_team(event)
    conversation, account = extract_conversation_and_account(event)
    conversation.reload
    return if conversation.team.nil?

    conversation.team.members.find_each do |member|
      NotificationBuilder.new(
        notification_type: 'team_conversation_assignment',
        user: member, account: account, primary_actor: conversation
      ).perform
    end
  end
end
