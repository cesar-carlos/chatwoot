# frozen_string_literal: true

# Prefer an existing WhatsApp contact_inbox source_id (groups @g.us, LID, etc.)
# over phone-derived ids from OSS ContactableInboxesService.
module Custom::Contacts::ContactableInboxesService
  private

  def whatsapp_contactable_inbox(inbox)
    existing = inbox.contact_inboxes.where(contact: @contact).order(created_at: :desc).first
    return { source_id: existing.source_id, inbox: inbox } if existing.present?

    super
  end
end
