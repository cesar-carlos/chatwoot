# frozen_string_literal: true

# Stamps opened_by=contact before incoming-driven reopen so conversation_opened
# automation conditions can filter on who reopened.
module Custom::Message::OpenedByTracking
  private

  def reopen_conversation
    stamp_opened_by_contact_on_reopen!
    super
  end

  def reopen_resolved_conversation
    stamp_opened_by_contact_on_reopen!
    super
  end

  def activate_from_snoozed!
    stamp_opened_by_contact_on_reopen!
    super
  end

  def open_evolution_pending_cycle_if_needed
    stamp_opened_by_contact_on_reopen!
    super
  end

  def stamp_opened_by_contact_on_reopen!
    return if history_import_message?
    return if conversation.muted?
    return unless incoming?
    return if conversation.open?

    Custom::Conversations::OpenedByStamper.stamp!(
      conversation,
      Custom::Conversations::OpenedByStamper::CONTACT
    )
  end
end
