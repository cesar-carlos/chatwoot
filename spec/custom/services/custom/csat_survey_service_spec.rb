# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CsatSurveyService do
  describe 'on Wavoip channels' do
    let(:account) { create(:account) }
    let(:channel) { create(:channel_wavoip, account: account) }
    let(:inbox) { channel.inbox }
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, status: :resolved)
    end

    before do
      account.enable_features!('channel_voice', 'channel_wavoip')
      inbox.update!(csat_survey_enabled: true)
    end

    it 'skips CSAT on voice-only inboxes' do
      service = described_class.new(conversation: conversation)

      expect(service.send(:should_send_csat_survey?)).to be false
    end
  end
end
