# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Voice::OutboundWhatsappCallBuilder do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:agent) { create(:user, account: account) }
  let(:conversation) do
    contact = create(:contact, account: account, phone_number: '+5511999999999')
    create(:conversation, account: account, inbox: inbox, contact: contact)
  end
  let(:provider_service) { instance_double(Whatsapp::Providers::WhatsappCloudService) }
  let(:sdp_offer) { 'v=0...offer' }
  let(:provider_call_id) { 'wacid_outbound_123' }

  before do
    allow(provider_service).to receive(:initiate_call).and_return(
      { 'calls' => [{ 'id' => provider_call_id }] }
    )
  end

  describe '.perform!' do
    it 'creates a Call and voice_call message with Meta provider id' do
      call = nil
      expect do
        call = described_class.perform!(
          conversation: conversation,
          agent: agent,
          sdp_offer: sdp_offer,
          provider_service: provider_service
        )
      end.to change(Call, :count).by(1)

      aggregate_failures do
        expect(call.provider).to eq('whatsapp')
        expect(call.provider_call_id).to eq(provider_call_id)
        expect(call.direction).to eq('outgoing')
        expect(call.status).to eq('ringing')
        expect(call.accepted_by_agent_id).to eq(agent.id)
        expect(call.meta['sdp_offer']).to eq(sdp_offer)
        expect(call.message_id).to be_present
      end
    end

    it 'raises when Meta does not return a call id' do
      allow(provider_service).to receive(:initiate_call).and_return({})

      expect do
        described_class.perform!(
          conversation: conversation,
          agent: agent,
          sdp_offer: sdp_offer,
          provider_service: provider_service
        )
      end.to raise_error(Voice::CallErrors::CallFailed, 'Meta did not return a call ID')
    end
  end
end
