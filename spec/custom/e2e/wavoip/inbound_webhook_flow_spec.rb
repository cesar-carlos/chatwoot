# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Wavoip inbound webhook flow', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account, phone_number: '+5566997193168') }
  let(:inbox) { channel.inbox }
  let!(:online_agent) { create(:user, account: account, role: :agent) }
  let(:payload) { JSON.parse(file_fixture('wavoip/call_create_incoming_live_caller_receiver.json').read) }

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
    create(:inbox_member, inbox: inbox, user: online_agent)
    online_agent.account_users.find_by(account: account).update!(availability: :online)
    allow(OnlineStatusTracker).to receive(:get_users_with_status).and_call_original
    allow(OnlineStatusTracker).to receive(:get_users_with_status)
      .with(account.id, user_ids: kind_of(Array), status: 'online')
      .and_return({ online_agent.id.to_s => 'online' })
  end

  it 'accepts webhook, creates Call, and broadcasts to online agents' do
    cable_payloads = []
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| cable_payloads << [stream, payload] }

    expect do
      post "/webhooks/wavoip/#{channel.webhook_key}", params: payload
    end.to have_enqueued_job(Wavoip::ProcessWebhookJob).with(inbox.id, hash_including('type' => 'CALL'))

    expect(response).to have_http_status(:accepted)

    perform_enqueued_jobs

    call = Call.find_by(inbox_id: inbox.id, provider: :wavoip, provider_call_id: payload['whatsapp_call_id'])
    aggregate_failures do
      expect(call).to be_present
      expect(call.incoming?).to be(true)
      expect(call.status).to eq('ringing')
    end

    incoming_events = cable_payloads.select { |_, body| body[:event] == 'voice_call.incoming' }
    expect(incoming_events.map(&:first)).to include(online_agent.pubsub_token)
  end
end
