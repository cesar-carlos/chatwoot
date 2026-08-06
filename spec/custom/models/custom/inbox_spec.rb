# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Inbox do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
  end

  describe '#more_responses?' do
    it 'returns true when the account uses an OpenAI hook even with exhausted credits' do
      create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })
      account.update!(limits: { captain_responses: 2 }, custom_attributes: { captain_responses_usage: 2 })

      expect(inbox.reload.send(:more_responses?)).to be(true)
    end

    it 'returns false when credits are exhausted and no hook exists' do
      account.update!(limits: { captain_responses: 2 }, custom_attributes: { captain_responses_usage: 2 })

      expect(inbox.reload.send(:more_responses?)).to be(false)
    end
  end
end
