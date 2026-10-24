# frozen_string_literal: true

module Custom::Twitter::DirectMessageParserService
  include Custom::Conversations::IncomingOpenedBy

  # set_inbox must run before outgoing_message? reads @inbox.
  def perform
    set_inbox
    super
  end

  def opened_by_origin
    if outgoing_message?
      Custom::Conversations::OpenedByStamper::AGENT
    else
      Custom::Conversations::OpenedByStamper::CONTACT
    end
  end
end
