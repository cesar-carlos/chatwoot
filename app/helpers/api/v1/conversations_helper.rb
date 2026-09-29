# frozen_string_literal: true

module Api::V1::ConversationsHelper
  # FORK: delegate the participation flag to the Custom overlay
  include Custom::Api::V1::ConversationsHelper
end
