class Custom::Notification::TeamAssignmentTransition
  ATTRIBUTE_KEY = 'team_notification_transition'.freeze
  ASSIGNMENT_ATTRIBUTES = %w[team_id assignee_id assignee_agent_bot_id ai_assignee_type].freeze

  def self.capture(conversation)
    assignment_changed = conversation.changed.intersect?(ASSIGNMENT_ATTRIBUTES)
    return unless assignment_changed || conversation.will_save_change_to_additional_attributes?

    # Read under the row lock so unrelated/stale writes cannot erase the delivery ledger.
    attributes = conversation.new_record? ? {} : Conversation.where(id: conversation.id).lock.pick(:additional_attributes)
    state = attributes.to_h[ATTRIBUTE_KEY]
    state = { 'revision' => SecureRandom.uuid, 'team_name' => conversation.team&.name, 'delivered_user_ids' => [] } if assignment_changed
    conversation.additional_attributes = conversation.additional_attributes.except(ATTRIBUTE_KEY)
    conversation.additional_attributes[ATTRIBUTE_KEY] = state if state
  end

  def self.state(conversation)
    conversation.additional_attributes.fetch(ATTRIBUTE_KEY, {})
  end

  def self.event_revision(event)
    attributes = event.data[:changed_attributes]&.with_indifferent_access&.[](:additional_attributes)&.last
    attributes&.dig(ATTRIBUTE_KEY, 'revision')
  end

  def self.deliver(conversation:, user:, revision:)
    return if revision.blank?

    conversation.reload.with_lock(requires_new: true) do
      state = state(conversation)
      return unless state['revision'] == revision
      return if state.fetch('delivered_user_ids', []).include?(user.id)

      notification = yield
      return unless notification&.persisted?

      state['delivered_user_ids'] = state.fetch('delivered_user_ids', []) | [user.id]
      # Persist creation and its receipt in the same transaction; callbacks run after both commit.
      conversation.update_columns(additional_attributes: conversation.additional_attributes.merge(ATTRIBUTE_KEY => state)) # rubocop:disable Rails/SkipsModelValidations
      notification
    end
  end
end
