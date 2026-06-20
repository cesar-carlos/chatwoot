# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::WavoipController, type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:payload) do
    {
      type: 'CALL',
      action: 'CREATE',
      whatsapp_call_id: 'webhook_ctrl_001',
      status: 'INCOMING_RING',
      direction: 'INCOMING',
      phone: channel.phone_number
    }
  end

  describe 'POST /webhooks/wavoip' do
    it 'accepts a valid webhook_key and enqueues processing' do
      expect do
        post "/webhooks/wavoip/#{channel.webhook_key}", params: payload
      end.to have_enqueued_job(Wavoip::ProcessWebhookJob).with(inbox.id, hash_including('type' => 'CALL'))

      expect(response).to have_http_status(:accepted)
    end

    it 'returns unauthorized for an invalid webhook_key' do
      post '/webhooks/wavoip/invalid-key', params: payload

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
