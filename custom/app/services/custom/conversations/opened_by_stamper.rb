# frozen_string_literal: true

# Persists who caused the current open episode on conversation.additional_attributes['opened_by'].
# Used by Automations (conversation_created / conversation_opened) as a filterable condition.
class Custom::Conversations::OpenedByStamper
  CONTACT = 'contact'
  AGENT = 'agent'
  PHONE = 'phone'
  ATTRIBUTE_KEY = 'opened_by'
  VALUES = [CONTACT, AGENT, PHONE].freeze

  class << self
    def merge_create_params(params)
      params = params.deep_dup.with_indifferent_access
      explicit = params.dig(:additional_attributes, ATTRIBUTE_KEY)
      value = normalize(explicit.presence || Current.conversation_opened_by)
      return params if value.blank?

      attrs = (params[:additional_attributes] || {}).stringify_keys
      attrs[ATTRIBUTE_KEY] = value
      params[:additional_attributes] = attrs
      params
    end

    def stamp!(conversation, value)
      return if conversation.blank?

      normalized = normalize(value)
      return if normalized.blank?

      attrs = conversation.additional_attributes.stringify_keys.merge(ATTRIBUTE_KEY => normalized)
      conversation.additional_attributes = attrs
      return unless conversation.persisted?

      # rubocop:disable Rails/SkipsModelValidations -- metadata only; must be visible to ConditionsFilterService before open!
      conversation.update_column(:additional_attributes, attrs)
      # rubocop:enable Rails/SkipsModelValidations
    end

    def normalize(value)
      str = value.to_s
      VALUES.include?(str) ? str : nil
    end
  end
end
