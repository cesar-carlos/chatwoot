require 'rails_helper'

RSpec.describe 'Team notification preferences', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  it 'lists the new flags and saves them independently without clearing older event choices' do
    put "/api/v1/accounts/#{account.id}/notification_settings",
        headers: user.create_new_auth_token,
        params: { notification_settings: {
          selected_email_flags: %w[email_conversation_assignment email_team_conversation_assignment],
          selected_push_flags: ['push_conversation_assignment']
        } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['all_email_flags']).to include('email_team_conversation_assignment')
    expect(response.parsed_body['all_push_flags']).to include('push_team_conversation_assignment')
    expect(response.parsed_body['selected_email_flags']).to match_array(%w[email_conversation_assignment email_team_conversation_assignment])
    expect(response.parsed_body['selected_push_flags']).to eq(['push_conversation_assignment'])
  end

  it 'does not change preferences for another account of the same user' do
    other_account = create(:account)
    create(:account_user, user: user, account: other_account)
    other_settings = user.notification_settings.find_by!(account: other_account)
    previous = other_settings.attributes.slice('email_flags', 'push_flags')
    put "/api/v1/accounts/#{account.id}/notification_settings",
        headers: user.create_new_auth_token,
        params: { notification_settings: {
          selected_email_flags: [], selected_push_flags: ['push_team_conversation_assignment']
        } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(other_settings.reload.attributes.slice('email_flags', 'push_flags')).to eq(previous)
  end
end
