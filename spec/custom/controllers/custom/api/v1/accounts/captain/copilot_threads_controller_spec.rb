# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Custom CopilotThreadsController BYOK', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:valid_params) do
    { message: 'Summarize this conversation', assistant_id: assistant.id, conversation_id: conversation.display_id }
  end

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    account.limits = { captain_responses: 2 }
    account.custom_attributes = { captain_responses_usage: 2 }
    account.save!
  end

  it 'enqueues a response job when the account has an OpenAI hook even with zero credits' do
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })

    expect do
      post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
           params: valid_params,
           headers: agent.create_new_auth_token,
           as: :json
    end.to have_enqueued_job(Captain::Copilot::ResponseJob)

    expect(response).to have_http_status(:success)
  end

  it 'returns the copilot limit message when credits are exhausted and no hook exists' do
    post "/api/v1/accounts/#{account.id}/captain/copilot_threads",
         params: valid_params,
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:success)
    expect(CopilotMessage.last.message['content']).to eq(I18n.t('captain.copilot_limit'))
  end
end
