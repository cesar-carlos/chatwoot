module Custom::BaseListener
  def extract_changed_attributes(event)
    changes = super
    return changes unless event.data[:conversation].is_a?(Conversation)

    changes&.map do |change|
      key = change.keys.first
      next change unless key.to_s == 'additional_attributes'

      values = change[key].transform_values do |value|
        value.is_a?(Hash) ? value.except(Custom::Notification::TeamAssignmentTransition::ATTRIBUTE_KEY) : value
      end
      { key => values }
    end
  end
end
