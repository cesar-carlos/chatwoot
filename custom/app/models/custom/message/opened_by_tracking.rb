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
    return if pending_origin_episode?

    Custom::Conversations::OpenedByStamper.stamp!(
      conversation,
      Custom::Conversations::OpenedByStamper::CONTACT
    )
  end

  # Pending phone/agent episodes stay with that opener. A contact reply must
  # not make conversation_opened look contact-started and send the welcome menu.
  def pending_origin_episode?
    return false unless conversation.pending?

    origin = conversation.additional_attributes&.[](Custom::Conversations::OpenedByStamper::ATTRIBUTE_KEY)
    [Custom::Conversations::OpenedByStamper::PHONE, Custom::Conversations::OpenedByStamper::AGENT].include?(origin)
  end
end
