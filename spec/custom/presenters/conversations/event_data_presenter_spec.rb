# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversations::EventDataPresenter do
  describe '#push_data' do
    it 'includes last_non_activity_message for websocket payloads' do
      conversation = create(:conversation)
      create(
        :message,
        conversation: conversation,
        account: conversation.account,
        message_type: :activity,
        content: 'assigned'
      )
      latest_message = create(
        :message,
        conversation: conversation,
        account: conversation.account,
        message_type: :incoming,
        content: 'latest preview'
      )

      payload = conversation.push_event_data

      expect(payload[:last_non_activity_message]).to include(
        id: latest_message.id,
        content: 'latest preview'
      )
    end
  end
end
