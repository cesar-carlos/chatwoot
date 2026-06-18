require 'rails_helper'

RSpec.describe 'Profile API (fork: groq_token)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:valid_groq_token) { "gsk_#{'a' * 40}" }

  describe 'PUT /api/v1/profile' do
    it 'persists groq_token and returns has_groq_token' do
      put '/api/v1/profile',
          params: { profile: { groq_token: valid_groq_token } },
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      json_response = response.parsed_body
      expect(json_response['has_groq_token']).to be(true)
      expect(json_response).not_to have_key('groq_token')

      agent.reload
      expect(agent.groq_token).to eq(valid_groq_token)
    end

    it 'does not clear groq_token on partial profile update' do
      agent.update!(groq_token: valid_groq_token)

      put '/api/v1/profile',
          params: { profile: { name: 'Updated Name', groq_token: '' } },
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      agent.reload
      expect(agent.groq_token).to eq(valid_groq_token)
      expect(response.parsed_body['has_groq_token']).to be(true)
    end
  end

  describe 'GET /api/v1/profile' do
    it 'returns has_groq_token without exposing groq_token value' do
      agent.update!(groq_token: valid_groq_token)

      get '/api/v1/profile',
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      json_response = response.parsed_body
      expect(json_response['has_groq_token']).to be(true)
      expect(json_response).not_to have_key('groq_token')
    end
  end
end
