# frozen_string_literal: true

# Inbox-scoped wrapper around Whatsapp::MessageDedupLock.
#
# Two Evolution Go inboxes in the same account can see the same WhatsApp
# message id (sender fromMe echo + recipient inbound). The OSS lock key is
# global by source_id, so the echo would swallow the inbound.
class Custom::Whatsapp::EvolutionGo::MessageDedupLock
  def self.build(inbox:, source_id:)
    Whatsapp::MessageDedupLock.new(lock_id(inbox, source_id))
  end

  def self.lock_id(inbox, source_id)
    "inbox-#{inbox.id}-#{source_id}"
  end
end
