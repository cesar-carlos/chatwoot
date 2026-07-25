# frozen_string_literal: true

class Custom::Inboxes::HistoryMigration::ConversationMerger
  pattr_initialize [:source_conversation!, :target_conversation!, :target_inbox!]

  def perform
    ActiveRecord::Base.transaction do
      reparent_messages!
      reparent_calls!
      reparent_mentions!
      reparent_participants!
      reparent_notifications!
      reparent_csat_responses!
      reparent_applied_slas!
      reparent_reporting_events!
      reparent_sla_events!
      clear_workflow_executions!
      merge_conversation_metadata!
      destroy_empty_source!
    end

    refresh_unread_counts!
    target_conversation.reload
  end

  private

  def reparent_messages!
    Message.where(conversation_id: source_conversation.id)
           .update_all( # rubocop:disable Rails/SkipsModelValidations
             conversation_id: target_conversation.id,
             inbox_id: target_inbox.id,
             updated_at: Time.current
           )
  end

  def reparent_calls!
    return unless defined?(Call)

    Call.where(conversation_id: source_conversation.id)
        .update_all( # rubocop:disable Rails/SkipsModelValidations
          conversation_id: target_conversation.id,
          inbox_id: target_inbox.id,
          updated_at: Time.current
        )
  end

  def reparent_mentions!
    Mention.where(conversation_id: source_conversation.id)
           .find_each do |mention|
      if Mention.exists?(user_id: mention.user_id, conversation_id: target_conversation.id)
        mention.destroy!
      else
        mention.update!(conversation_id: target_conversation.id)
      end
    end
  end

  def reparent_participants!
    existing_user_ids = target_conversation.conversation_participants.pluck(:user_id)
    ConversationParticipant.where(conversation_id: source_conversation.id)
                           .where.not(user_id: existing_user_ids)
                           .update_all( # rubocop:disable Rails/SkipsModelValidations
                             conversation_id: target_conversation.id,
                             updated_at: Time.current
                           )
    ConversationParticipant.where(conversation_id: source_conversation.id).delete_all
  end

  def reparent_notifications!
    Notification.where(primary_actor_type: 'Conversation', primary_actor_id: source_conversation.id)
                .update_all(primary_actor_id: target_conversation.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    Notification.where(secondary_actor_type: 'Conversation', secondary_actor_id: source_conversation.id)
                .update_all(secondary_actor_id: target_conversation.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def reparent_csat_responses!
    source_csats = CsatSurveyResponse.where(conversation_id: source_conversation.id)
    return if source_csats.none?

    # Conversation has_one csat — keep target's response when both exist.
    if CsatSurveyResponse.exists?(conversation_id: target_conversation.id)
      source_csats.delete_all
    else
      source_csats.update_all(conversation_id: target_conversation.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def reparent_applied_slas!
    return unless defined?(AppliedSla)

    AppliedSla.where(conversation_id: source_conversation.id).find_each do |source_applied_sla|
      target_applied_sla = AppliedSla.find_by(
        account_id: source_applied_sla.account_id,
        sla_policy_id: source_applied_sla.sla_policy_id,
        conversation_id: target_conversation.id
      )

      if target_applied_sla
        SlaEvent.where(applied_sla_id: source_applied_sla.id)
                .update_all( # rubocop:disable Rails/SkipsModelValidations
                  applied_sla_id: target_applied_sla.id,
                  conversation_id: target_conversation.id,
                  inbox_id: target_inbox.id,
                  updated_at: Time.current
                )
        source_applied_sla.destroy!
      else
        source_applied_sla.update!(conversation_id: target_conversation.id)
        SlaEvent.where(applied_sla_id: source_applied_sla.id)
                .update_all( # rubocop:disable Rails/SkipsModelValidations
                  conversation_id: target_conversation.id,
                  inbox_id: target_inbox.id,
                  updated_at: Time.current
                )
      end
    end
  end

  def reparent_reporting_events!
    ReportingEvent.where(conversation_id: source_conversation.id)
                  .update_all( # rubocop:disable Rails/SkipsModelValidations
                    conversation_id: target_conversation.id,
                    inbox_id: target_inbox.id,
                    updated_at: Time.current
                  )
  end

  def reparent_sla_events!
    return unless defined?(SlaEvent)

    # Events still tied to the source conversation after applied_sla remount.
    SlaEvent.where(conversation_id: source_conversation.id)
            .update_all( # rubocop:disable Rails/SkipsModelValidations
              conversation_id: target_conversation.id,
              inbox_id: target_inbox.id,
              updated_at: Time.current
            )
  end

  def clear_workflow_executions!
    return unless defined?(ConversationWorkflowRuleExecution)

    # FK to conversations — must clear before destroy. Dedup uniqueness makes
    # reparent fragile; audit rows for the source conversation are disposable.
    ConversationWorkflowRuleExecution.where(conversation_id: source_conversation.id).delete_all
  end

  def merge_conversation_metadata!
    target_conversation.label_list.add(source_conversation.label_list, parse: true)
    target_conversation.custom_attributes = (source_conversation.custom_attributes || {})
                                            .merge(target_conversation.custom_attributes || {})

    if target_conversation.assignee_id.blank? && source_conversation.assignee_id.present? &&
       target_inbox.members.exists?(source_conversation.assignee_id)
      target_conversation.assignee_id = source_conversation.assignee_id
    end

    target_conversation.save!
  end

  def destroy_empty_source!
    raise StandardError, 'source conversation still has messages' if source_conversation.messages.exists?

    source_conversation.destroy!
  end

  def refresh_unread_counts!
    Conversations::UnreadCounts::Refresher.new(target_conversation.reload).perform
  end
end
