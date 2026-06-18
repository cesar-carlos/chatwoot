require 'rails_helper'

RSpec.describe 'Token Validation API', type: :request do
  describe 'GET /validate_token' do
    let(:account) { create(:account) }

    context 'when it is an invalid token' do
      it 'returns unauthorized' do
        get '/auth/validate_token'
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is a valid token' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns user payload' do
        get '/auth/validate_token',
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(response.body).to include('payload')
      end

      it 'returns has_groq_token without exposing groq_token value' do
        agent.update!(groq_token: "gsk_#{'a' * 40}")

        get '/auth/validate_token',
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.dig('payload', 'data', 'has_groq_token')).to be(true)
        expect(json_response.dig('payload', 'data')).not_to have_key('groq_token')
      end
    end
  end
end
