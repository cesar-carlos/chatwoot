# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::IncomingMessageService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'instance_name' => 'test-instance',
        'api_key' => 'TEST-KEY'
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999999999') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: 'MSG_STATUS_123'
    ).tap { |record| record.update!(status: :delivered) }
  end

  describe 'Evolution status updates' do
    it 'does not downgrade message status' do
      message

      described_class.new(
        inbox: inbox,
        params: {
          statuses: [{ id: 'MSG_STATUS_123', status: 'sent', timestamp: Time.current.to_i.to_s, recipient_id: '5511999999999' }],
          phone_number: channel.phone_number
        }
      ).perform

      expect(message.reload.status).to eq('delivered')
    end

    it 'promotes message status to read' do
      message

      described_class.new(
        inbox: inbox,
        params: {
          statuses: [{ id: 'MSG_STATUS_123', status: 'read', timestamp: Time.current.to_i.to_s, recipient_id: '5511999999999' }],
          phone_number: channel.phone_number
        }
      ).perform

      expect(message.reload.status).to eq('read')
    end

    it 'logs when status update cannot find the message' do
      allow(Rails.logger).to receive(:warn)

      described_class.new(
        inbox: inbox,
        params: {
          statuses: [{ id: 'MISSING_ID', status: 'read', timestamp: Time.current.to_i.to_s, recipient_id: '5511999999999' }],
          phone_number: channel.phone_number
        }
      ).perform

      expect(Rails.logger).to have_received(:warn).with(
        '[EVOLUTION] status update skipped message not found source_id=MISSING_ID status=read'
      )
    end
  end
end
