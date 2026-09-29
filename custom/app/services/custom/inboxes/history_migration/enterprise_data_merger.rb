# frozen_string_literal: true

# Preserves Enterprise/Captain records before the source conversation is
# destroyed by ConversationMerger.
class Custom::Inboxes::HistoryMigration::EnterpriseDataMerger
  pattr_initialize [:source_conversation!, :target_conversation!, :target_inbox!]

  def self.perform(source_conversation, target_conversation, target_inbox)
    new(source_conversation: source_conversation, target_conversation: target_conversation, target_inbox: target_inbox).perform
  end

  def perform
    reparent_conversation_outcomes!
    reparent_captain_responses!
    reparent_captain_faq_observations!
    reparent_captain_message_reports!
  end

  private

  def reparent_conversation_outcomes!
    return unless defined?(ConversationOutcome)

    state = target_outcome_state
    source_outcomes.chronological.each do |outcome|
      outcome.update!(outcome_attributes(outcome, state))
      state[:initial] ||= outcome.episode_trigger == 'initial'
      state[:open] ||= outcome.ended_at.nil?
    end
  end

  def source_outcomes
    ConversationOutcome.where(conversation_id: source_conversation.id)
  end

  def target_outcome_state
    scope = ConversationOutcome.where(conversation_id: target_conversation.id)
    {
      initial: scope.exists?(episode_trigger: 'initial'),
      open: scope.exists?(ended_at: nil)
    }
  end

  def outcome_attributes(outcome, state)
    attrs = { conversation_id: target_conversation.id, inbox_id: target_inbox.id }
    attrs[:episode_trigger] = 'reopen' if outcome.episode_trigger == 'initial' && state[:initial]
    return attrs unless outcome.ended_at.nil? && state[:open]

    attrs.merge(ended_at: [outcome.started_at, source_conversation.last_activity_at].compact.max)
  end

  def reparent_captain_responses!
    return unless defined?(Captain::AssistantResponse)

    Captain::AssistantResponse
      .where(documentable_type: 'Conversation', documentable_id: source_conversation.id)
      .update_all(documentable_id: target_conversation.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def reparent_captain_faq_observations!
    return unless defined?(Captain::FaqObservation)

    Captain::FaqObservation.where(conversation_id: source_conversation.id).find_each do |observation|
      duplicate = observation.faq_suggestion_id.present? && Captain::FaqObservation.exists?(
        conversation_id: target_conversation.id,
        faq_suggestion_id: observation.faq_suggestion_id
      )
      duplicate ? observation.destroy! : observation.update!(conversation_id: target_conversation.id)
    end
  end

  def reparent_captain_message_reports!
    return unless defined?(Captain::MessageReport)

    Captain::MessageReport.where(conversation_id: source_conversation.id)
                          .update_all( # rubocop:disable Rails/SkipsModelValidations
                            conversation_id: target_conversation.id,
                            updated_at: Time.current
                          )
  end
end
