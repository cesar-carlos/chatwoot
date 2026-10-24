# frozen_string_literal: true

module Custom::Tiktok::MessageService
  include Custom::Conversations::IncomingOpenedBy

  def opened_by_origin
    if outgoing_echo || outgoing_message?
      Custom::Conversations::OpenedByStamper::PHONE
    else
      Custom::Conversations::OpenedByStamper::CONTACT
    end
  end
end
