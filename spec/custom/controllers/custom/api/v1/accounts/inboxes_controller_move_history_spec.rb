# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inbox history migration API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:source_inbox) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
  end
  let(:target_inbox) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
  end

  before do
    create(:inbox_member, user: agent, inbox: source_inbox)
    create(:inbox_member, user: agent, inbox: target_inbox)
  end

  describe 'POST /api/v1/accounts/:account_id/inboxes/:id/move_history' do
    it 'enqueues a migration for administrators' do
      expect do
        post "/api/v1/accounts/#{account.id}/inboxes/#{source_inbox.id}/move_history",
             params: { target_inbox_id: target_inbox.id },
             headers: admin.create_new_auth_token
      end.to have_enqueued_job(Custom::Inboxes::HistoryMigrationJob)

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['status']).to eq('pending')
      expect(body['source_inbox_id']).to eq(source_inbox.id)
      expect(body['target_inbox_id']).to eq(target_inbox.id)
      expect(InboxHistoryMigration.count).to eq(1)
    end

    it 'rejects agents' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{source_inbox.id}/move_history",
           params: { target_inbox_id: target_inbox.id },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects incompatible destination inboxes' do
      email_inbox = create(:channel_email, account: account).inbox

      post "/api/v1/accounts/#{account.id}/inboxes/#{source_inbox.id}/move_history",
           params: { target_inbox_id: email_inbox.id },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('incompatible_channels')
    end
  end

  describe 'GET /api/v1/accounts/:account_id/inboxes/:id/move_history_status' do
    it 'returns the latest migration status' do
      migration = InboxHistoryMigration.create!(
        account: account,
        source_inbox: source_inbox,
        target_inbox: target_inbox,
        status: 'completed',
        stats: { 'moved' => 3 }
      )

      get "/api/v1/accounts/#{account.id}/inboxes/#{source_inbox.id}/move_history_status",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(migration.id)
      expect(response.parsed_body['stats']['moved']).to eq(3)
    end

    it 'expires a stale running migration so the UI can unblock' do
      migration = InboxHistoryMigration.create!(
        account: account,
        source_inbox: source_inbox,
        target_inbox: target_inbox,
        status: 'running',
        started_at: 3.hours.ago,
        heartbeat_at: 3.hours.ago
      )

      get "/api/v1/accounts/#{account.id}/inboxes/#{source_inbox.id}/move_history_status",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('failed')
      expect(migration.reload.status).to eq('failed')
      expect(migration.error_message).to include('heartbeat timed out')
    end
  end
end
