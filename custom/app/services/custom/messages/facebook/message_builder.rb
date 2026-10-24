# frozen_string_literal: true

module Custom::Messages::Facebook::MessageBuilder
  include Custom::Conversations::IncomingOpenedBy

  def opened_by_origin
    if @outgoing_echo
      Custom::Conversations::OpenedByStamper::PHONE
    else
      Custom::Conversations::OpenedByStamper::CONTACT
    end
  end
end
