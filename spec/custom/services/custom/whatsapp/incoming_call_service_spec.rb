# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::IncomingCallService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:provider_call_id) { 'wacid_outbound_scope' }
  let(:agent) { create(:user, account: account) }
  let(:call) do
    conversation = create(:conversation, account: account, inbox: inbox)
    create(:call, account: account, inbox: inbox, conversation: conversation, contact: conversation.contact,
                  provider: :whatsapp, direction: :outgoing, status: 'ringing', provider_call_id: provider_call_id,
                  accepted_by_agent: agent)
  end

  before do
    account.enable_features!('channel_voice')
    channel.provider_config = channel.provider_config.merge('source' => 'embedded_signup', 'calling_enabled' => true)
    channel.save!
    allow(ActionCable.server).to receive(:broadcast)
  end

  it 'sends outbound_connected only to the agent who started the call' do
    params = {
      calls: [{
        id: provider_call_id,
        event: 'connect',
        session: { sdp: "v=0\r\na=setup:actpass\r\n", sdp_type: 'answer' }
      }]
    }

    expect(call).to be_outgoing

    described_class.new(inbox: inbox, params: params).perform

    expect(call.reload.meta['sdp_answer']).to include('a=setup:active')
    expect(ActionCable.server).to have_received(:broadcast).with(
      agent.pubsub_token,
      hash_including(event: 'voice_call.outbound_connected')
    )
    expect(ActionCable.server).not_to have_received(:broadcast).with(
      "account_#{account.id}",
      hash_including(event: 'voice_call.outbound_connected')
    )
  end
end
