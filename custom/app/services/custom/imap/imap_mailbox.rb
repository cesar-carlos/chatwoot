# frozen_string_literal: true

module Custom::Imap::ImapMailbox
  def process(...)
    Custom::Conversations::OpenedByStamper.with_current(Custom::Conversations::OpenedByStamper::CONTACT) { super }
  end
end
