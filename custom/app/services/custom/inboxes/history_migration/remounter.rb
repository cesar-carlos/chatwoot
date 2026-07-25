# frozen_string_literal: true

class Custom::Inboxes::HistoryMigration::Remounter
  pattr_initialize [:conversation!, :target_inbox!, :target_contact_inbox!, :source_inbox!]

  def perform
    ActiveRecord::Base.transaction do
      remount_conversation!
      remount_messages!
      remount_reporting_events!
      remount_sla_events!
    end

    refresh_unread_counts!
    conversation
  end

  private

  def remount_conversation!
    conversation.update!(
      inbox_id: target_inbox.id,
      contact_inbox_id: target_contact_inbox.id
    )
    clear_assignee_if_not_member!
  end

  def clear_assignee_if_not_member!
    return if conversation.assignee_id.blank?
    return if target_inbox.members.exists?(conversation.assignee_id)

    conversation.update!(assignee_id: nil)
  end

  def remount_messages!
    Message.where(conversation_id: conversation.id)
           .update_all(inbox_id: target_inbox.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def remount_reporting_events!
    ReportingEvent.where(conversation_id: conversation.id)
                  .update_all(inbox_id: target_inbox.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def remount_sla_events!
    return unless defined?(SlaEvent)

    SlaEvent.where(conversation_id: conversation.id)
            .update_all(inbox_id: target_inbox.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def refresh_unread_counts!
    Conversations::UnreadCounts::Refresher.new(
      conversation.reload,
      changed_attributes: { 'inbox_id' => [source_inbox.id, target_inbox.id] }
    ).perform
  end
end
