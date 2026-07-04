# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Accounts::CallsController, type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :wavoip,
      direction: :incoming,
      status: 'ringing',
      provider_call_id: 'wavoip_patch_001'
    )
  end

  before do
    account.enable_features!('channel_voice')
    create(:inbox_member, user: agent, inbox: inbox)
    create(:inbox_member, user: other_agent, inbox: inbox)
  end

  describe 'PATCH /api/v1/accounts/:account_id/calls/:id' do
    it 'records accepted_by_agent_id for the authenticated agent' do
      patch "/api/v1/accounts/#{account.id}/calls/#{call.id}",
            headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(call.reload.accepted_by_agent_id).to eq(agent.id)
      expect(response.parsed_body['accepted_by_agent_id']).to eq(agent.id)
    end

    it 'broadcasts voice_call.accepted when the agent accepts' do
      payloads = []
      allow(ActionCable.server).to receive(:broadcast) { |_stream, payload| payloads << payload }

      patch "/api/v1/accounts/#{account.id}/calls/#{call.id}",
            headers: agent.create_new_auth_token

      accepted = payloads.find { |p| p[:event] == 'voice_call.accepted' }
      expect(accepted).to be_present
      expect(accepted[:data][:accepted_by_agent_id]).to eq(agent.id)
      expect(accepted[:data][:call_id]).to eq(call.provider_call_id)
    end

    it 'returns conflict when another agent already accepted' do
      call.update!(accepted_by_agent_id: other_agent.id)

      patch "/api/v1/accounts/#{account.id}/calls/#{call.id}",
            headers: agent.create_new_auth_token

      expect(response).to have_http_status(:conflict)
      expect(call.reload.accepted_by_agent_id).to eq(other_agent.id)
    end

    it 'records join intent before accept' do
      post "/api/v1/accounts/#{account.id}/calls/#{call.id}/join",
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(Wavoip::Calls::JoiningAgentCache.read(call.id)).to eq(agent.id)
    end

    it 'returns conflict on join when another agent already accepted' do
      call.update!(accepted_by_agent_id: other_agent.id)

      post "/api/v1/accounts/#{account.id}/calls/#{call.id}/join",
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:conflict)
    end

    it 'returns unauthorized when the agent is not an inbox member' do
      outsider = create(:user, account: account, role: :agent)

      patch "/api/v1/accounts/#{account.id}/calls/#{call.id}",
            headers: outsider.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unprocessable_entity for completed calls' do
      call.update!(status: 'completed')

      patch "/api/v1/accounts/#{account.id}/calls/#{call.id}",
            headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns unprocessable_entity for non-wavoip calls' do
      twilio_call = create(
        :call,
        account: account,
        inbox: inbox,
        conversation: conversation,
        contact: conversation.contact,
        provider: :twilio,
        status: 'ringing'
      )

      patch "/api/v1/accounts/#{account.id}/calls/#{twilio_call.id}",
            headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
