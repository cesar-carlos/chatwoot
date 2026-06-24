# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::PhoneOutgoingSyncService do
  subject(:service) { described_class.new(channel: channel, data: data) }

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
        'api_key' => 'TEST-INSTANCE-API-KEY',
        'ignore_from_me_echo' => false
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:data) do
    JSON.parse(Rails.root.join('spec/fixtures/evolution/messages_upsert_text.json').read)['data'].merge(
      'key' => {
        'id' => 'PHONE-SENT-MSG-001',
        'fromMe' => true,
        'remoteJid' => '556696971841@s.whatsapp.net',
        'remoteJidAlt' => '556696971841@s.whatsapp.net'
      }
    )
  end

  describe '#perform' do
    it 'creates an outgoing message for a phone-sent text' do
      expect { service.perform }.to change(Message, :count).by(1)

      message = Message.last
      aggregate_failures do
        expect(message.inbox).to eq(inbox)
        expect(message.outgoing?).to be(true)
        expect(message.content).to eq('Oi')
        expect(message.source_id).to eq('PHONE-SENT-MSG-001')
        expect(message.content_attributes['phone_sent']).to be(true)
      end
    end

    it 'creates a group outgoing message using GroupContactService' do
      channel.update_columns(
        provider_config: channel.provider_config.merge('groups_ignore' => false, 'ignore_jids' => [])
      )
      channel.reload
      group_data = data.merge(
        'key' => {
          'id' => 'GROUP-SENT-001',
          'fromMe' => true,
          'remoteJid' => '120363123456789012@g.us',
          'participant' => '5511999999999@s.whatsapp.net'
        }
      )
      allow(Custom::Whatsapp::Evolution::GroupMetadataService).to receive(:new).and_return(
        instance_double(Custom::Whatsapp::Evolution::GroupMetadataService, display_name: 'Team (GROUP)')
      )

      expect do
        described_class.new(channel: channel, data: group_data).perform
      end.to change(Message, :count).by(1)

      contact_inbox = ContactInbox.last
      expect(contact_inbox.source_id).to eq('120363123456789012@g.us')
      expect(contact_inbox.contact.phone_number).to be_nil
    end

    it 'skips duplicate Chatwoot outbound echoes by source_id' do
      contact = create(:contact, account: account, phone_number: '+5566996971841')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566996971841')
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        source_id: 'PHONE-SENT-MSG-001',
        content: 'already sent from Chatwoot'
      )

      expect { service.perform }.not_to change(Message, :count)
    end

    it 'enqueues async media download for phone-sent media' do
      media_data = data.merge(
        'messageType' => 'imageMessage',
        'key' => {
          'id' => 'PHONE-SENT-MEDIA-001',
          'fromMe' => true,
          'remoteJid' => '556696971841@s.whatsapp.net',
          'remoteJidAlt' => '556696971841@s.whatsapp.net'
        },
        'message' => {
          'imageMessage' => {
            'caption' => 'Photo from phone',
            'mimetype' => 'image/jpeg'
          }
        }
      )
      media_service = described_class.new(channel: channel, data: media_data)

      expect do
        media_service.perform
      end.to have_enqueued_job(Custom::Whatsapp::Evolution::MediaDownloadJob)
    end
  end
end
