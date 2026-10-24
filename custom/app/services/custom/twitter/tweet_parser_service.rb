# frozen_string_literal: true

module Custom::Twitter::TweetParserService
  include Custom::Conversations::IncomingOpenedBy

  def opened_by_origin
    message_type == :outgoing ? Custom::Conversations::OpenedByStamper::AGENT : Custom::Conversations::OpenedByStamper::CONTACT
  end
end
