# frozen_string_literal: true

# Picks the inbox link that already carries the conversation.
# A second link that only spells the same Brazil number differently must not win.
class Custom::Whatsapp::ContactInboxPreference
  def self.choose(contact_inboxes)
    rows = Array(contact_inboxes).compact
    return if rows.empty?
    return rows.first if rows.one?

    rows.max_by { |contact_inbox| rank(contact_inbox) }
  end

  def self.rank(contact_inbox)
    last_activity = contact_inbox.conversations.maximum(:last_activity_at)
    [last_activity.present? ? 1 : 0, last_activity.to_i, -contact_inbox.id]
  end
  private_class_method :rank
end
