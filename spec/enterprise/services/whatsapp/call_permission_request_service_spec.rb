# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::CallPermissionRequestService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:agent) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+15550001111') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:provider_service) { instance_double(Whatsapp::Providers::WhatsappCloudService) }

  before do
    allow(Whatsapp::Providers::WhatsappCloudService).to receive(:new).and_return(provider_service)
  end

  describe '#perform' do
    it 'sends permission request and records wamid' do
      allow(provider_service).to receive(:send_call_permission_request)
        .and_return({ 'messages' => [{ 'id' => 'wamid.permission' }] })

      status = described_class.new(conversation: conversation, agent: agent).perform

      expect(status).to eq(:permission_requested)
      expect(conversation.reload.additional_attributes['call_permission_request_message_id']).to eq('wamid.permission')
    end

    it 'returns permission_pending when throttled' do
      allow(provider_service).to receive(:send_call_permission_request)

      conversation.update!(
        additional_attributes: { 'call_permission_requested_at' => 1.minute.ago.iso8601 }
      )

      status = described_class.new(conversation: conversation, agent: agent).perform

      expect(status).to eq(:permission_pending)
      expect(provider_service).not_to have_received(:send_call_permission_request)
    end

    it 'returns failed when provider transport fails' do
      allow(provider_service).to receive(:send_call_permission_request)
        .and_raise(StandardError, 'network down')

      status = described_class.new(conversation: conversation, agent: agent).perform

      expect(status).to eq(:failed)
    end
  end
end
