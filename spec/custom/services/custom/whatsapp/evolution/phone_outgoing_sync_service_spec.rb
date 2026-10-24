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

  def apply_provider_config!(channel, attrs)
    channel.provider_config = channel.provider_config.merge(attrs)
    channel.save!(validate: false)
    channel.reload
  end

  describe '#perform' do
    it 'creates an outgoing message for a phone-sent text' do
      expect { service.perform }.to change { inbox.messages.count }.by(1)

      message = inbox.messages.find_by!(source_id: 'PHONE-SENT-MSG-001')
      aggregate_failures do
        expect(message.inbox).to eq(inbox)
        expect(message.outgoing?).to be(true)
        expect(message.content).to eq('Oi')
        expect(message.source_id).to eq('PHONE-SENT-MSG-001')
        expect(message.content_attributes['phone_sent']).to be(true)
        expect(message.content_attributes['external_echo']).to be(true)
        expect(message.conversation.additional_attributes['opened_by']).to eq('phone')
      end
    end

    it 'creates a group outgoing message using GroupContactService' do
      apply_provider_config!(channel, 'groups_ignore' => false, 'ignore_jids' => [])
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

    it 'keeps a Chatwoot send as the agent message when its WhatsApp id is already stored' do
      contact = create(:contact, account: account, phone_number: '+556696971841')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '556696971841')
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      agent_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        source_id: 'PHONE-SENT-MSG-001',
        content: 'Oi'
      )

      expect { service.perform }.not_to change(Message, :count)

      agent_message.reload
      expect(agent_message.sender).to be_a(User)
      expect(agent_message.content_attributes['external_echo']).not_to be(true)
      expect(agent_message.content_attributes['phone_sent']).not_to be(true)
    end

    it 'creates a phone-identified copy when the Chatwoot send has not stored its WhatsApp id yet' do
      contact = create(:contact, account: account, phone_number: '+556696971841')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '556696971841')
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      agent_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        source_id: nil,
        content: 'Oi'
      )

      expect { service.perform }.to change(Message, :count).by(1)

      echo = inbox.messages.find_by!(source_id: 'PHONE-SENT-MSG-001')
      agent_message.reload
      expect(agent_message.id).not_to eq(echo.id)
      expect(agent_message.content_attributes['external_echo']).not_to be(true)
      expect(echo.sender).to be_nil
      expect(echo.content_attributes['external_echo']).to be(true)
      expect(echo.content_attributes['phone_sent']).to be(true)
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

    it 'reopens a resolved single-history conversation as phone' do
      service.perform
      inbox.update!(lock_to_single_conversation: true)
      conversation = inbox.conversations.order(:id).last
      conversation.update!(status: :resolved, additional_attributes: { 'opened_by' => 'contact' })
      follow_up = data.merge('key' => data['key'].merge('id' => 'PHONE-SENT-MSG-002'))

      described_class.new(channel: channel, data: follow_up).perform

      expect(conversation.reload).to be_open
      expect(conversation.additional_attributes['opened_by']).to eq('phone')
    end

    it 'keeps a pending episode origin when the phone sends again' do
      service.perform
      conversation = inbox.conversations.order(:id).last
      conversation.update!(status: :pending, additional_attributes: { 'opened_by' => 'contact' })
      follow_up = data.merge('key' => data['key'].merge('id' => 'PHONE-SENT-MSG-003'))

      described_class.new(channel: channel, data: follow_up).perform

      expect(conversation.reload).to be_pending
      expect(conversation.additional_attributes['opened_by']).to eq('contact')
    end

    it 'raises LockAcquisitionError when the dedup lock is busy' do
      dedup_lock = instance_double(Whatsapp::MessageDedupLock, acquire!: false)
      allow(Whatsapp::MessageDedupLock).to receive(:new).with('PHONE-SENT-MSG-001').and_return(dedup_lock)

      expect { service.perform }.to raise_error(
        MutexApplicationJob::LockAcquisitionError,
        /dedup lock busy/
      )
    end

    it "does not delete another worker's lock when the dedup lock is busy" do
      dedup_lock = instance_double(Whatsapp::MessageDedupLock, acquire!: false, release!: nil)
      allow(Whatsapp::MessageDedupLock).to receive(:new).with('PHONE-SENT-MSG-001').and_return(dedup_lock)

      expect { service.perform }.to raise_error(MutexApplicationJob::LockAcquisitionError)
      expect(dedup_lock).not_to have_received(:release!)
    end

    it 'releases its own dedup lock on failure so an immediate retry is not blocked for 1 day' do
      allow(Conversations::Resolver).to receive(:new).and_raise(StandardError, 'boom')

      expect { service.perform }.to raise_error(StandardError, 'boom')

      fresh_lock = Whatsapp::MessageDedupLock.new('PHONE-SENT-MSG-001')
      expect(fresh_lock.acquire!).to be(true)
    end
  end
end
