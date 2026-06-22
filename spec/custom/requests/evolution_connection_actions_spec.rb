# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Evolution connection actions API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'instance_name' => 'test-instance',
        'api_key' => 'TEST-INSTANCE-API-KEY',
        'connection_status' => 'close'
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:connection_service) { instance_double(Custom::Whatsapp::Evolution::ConnectionService) }

  before do
    sign_in admin
    allow(Custom::Whatsapp::Evolution::ConnectionService).to receive(:new).and_return(connection_service)
    allow(connection_service).to receive(:connection_payload).and_return(
      connection_status: 'connecting',
      phone_number: channel.phone_number,
      qrcode_base64: 'data:image/png;base64,abc',
      qrcode_code: '2@pair'
    )
  end

  describe 'POST evolution_reconnect' do
    it 'reconnects and returns connection payload' do
      allow(connection_service).to receive(:reconnect!)

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/evolution_reconnect"

      expect(response).to have_http_status(:success)
      expect(connection_service).to have_received(:reconnect!)
      expect(response.parsed_body['qrcode_base64']).to eq('data:image/png;base64,abc')
    end
  end

  describe 'POST evolution_logout' do
    it 'logs out and returns connection payload' do
      allow(connection_service).to receive(:logout!)

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/evolution_logout"

      expect(response).to have_http_status(:success)
      expect(connection_service).to have_received(:logout!)
    end
  end

  describe 'POST evolution_restart' do
    it 'restarts and returns connection payload' do
      allow(connection_service).to receive(:restart!)

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/evolution_restart"

      expect(response).to have_http_status(:success)
      expect(connection_service).to have_received(:restart!)
    end
  end
end
