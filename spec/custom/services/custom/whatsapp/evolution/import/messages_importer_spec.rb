# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::Import::MessagesImporter do
  subject(:importer) { described_class.new(runtime: runtime, api_client: api_client, channel: channel) }

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
        'api_key' => 'TEST-KEY',
        'import_messages' => true
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:runtime) { Custom::Whatsapp::Evolution::Import::Runtime.new(channel: channel) }
  let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }
  let(:remote_jid) { '5511999999999@s.whatsapp.net' }
  let(:incoming_record) do
    {
      'key' => { 'id' => 'IMPORT-MSG-1', 'fromMe' => false, 'remoteJid' => remote_jid },
      'pushName' => 'Alice',
      'messageType' => 'conversation',
      'message' => { 'conversation' => 'Hello from import' },
      'messageTimestamp' => 5.days.ago.to_i
    }
  end

  before do
    inbox
    runtime.persist_cursor!(
      'phase' => 'messages',
      'remote_jids' => [remote_jid],
      'message_jid_index' => 0,
      'message_page' => 1
    )
  end

  def stub_find_messages(records, pages: 1)
    allow(api_client).to receive(:find_messages).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'messages' => { 'records' => records, 'pages' => pages } }
      )
    )
  end

  describe '#import_batch!' do
    it 'creates the incoming message and marks the import completed' do
      stub_find_messages([incoming_record])

      importer.import_batch!

      message = inbox.messages.find_by(source_id: 'IMPORT-MSG-1')
      expect(message).to be_present
      expect(message.content).to eq('Hello from import')
      expect(channel.reload.provider_config['import_status']).to eq('completed')
    end

    it 'wraps incoming message processing in the shared MessageMutex keyed by remoteJid' do
      stub_find_messages([incoming_record])
      allow(Custom::Whatsapp::Evolution::MessageMutex).to receive(:with_lock).and_call_original

      importer.import_batch!

      expect(Custom::Whatsapp::Evolution::MessageMutex).to have_received(:with_lock).with(channel, remote_jid)
    end

    it 'skips the record without raising when the message lock is contended' do
      stub_find_messages([incoming_record])
      allow(Custom::Whatsapp::Evolution::MessageMutex).to receive(:with_lock)
        .and_raise(MutexApplicationJob::LockAcquisitionError, 'busy')
      allow(Rails.logger).to receive(:warn)

      expect { importer.import_batch! }.not_to raise_error
      expect(inbox.messages.find_by(source_id: 'IMPORT-MSG-1')).to be_nil
      expect(Rails.logger).to have_received(:warn).with(
        /\[EVOLUTION\] import message lock contention sender=#{Regexp.escape(remote_jid)}/
      )
    end

    it 'marks a fromMe history message as sent from the phone' do
      phone_record = incoming_record.merge(
        'key' => { 'id' => 'IMPORT-PHONE-1', 'fromMe' => true, 'remoteJid' => remote_jid },
        'message' => { 'conversation' => 'Sent from the phone' }
      )
      stub_find_messages([phone_record])

      importer.import_batch!

      message = inbox.messages.find_by!(source_id: 'IMPORT-PHONE-1')
      expect(message).to be_outgoing
      expect(message.sender).to be_nil
      expect(message.content_attributes['phone_sent']).to be(true)
      expect(message.content_attributes['external_echo']).to be(true)
    end

    it 'stamps the phone origin on an older fromMe import that has no sender' do
      conversation = create(:conversation, account: account, inbox: inbox)
      existing = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        source_id: 'IMPORT-PHONE-OLD',
        content: 'Already imported',
        content_attributes: { 'history_import' => true }
      )
      existing.update_columns(sender_id: nil, sender_type: nil) # rubocop:disable Rails/SkipsModelValidations
      agent_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        source_id: 'IMPORT-AGENT-ECHO',
        content_attributes: {}
      )
      stub_find_messages(
        [
          incoming_record.merge(
            'key' => { 'id' => 'IMPORT-PHONE-OLD', 'fromMe' => true, 'remoteJid' => remote_jid }
          ),
          incoming_record.merge(
            'key' => { 'id' => 'IMPORT-AGENT-ECHO', 'fromMe' => true, 'remoteJid' => remote_jid }
          )
        ]
      )

      importer.import_batch!

      expect(existing.reload.content_attributes['external_echo']).to be(true)
      expect(existing.content_attributes['phone_sent']).to be(true)
      expect(agent_message.reload.content_attributes['external_echo']).not_to be(true)
    end

    it 'advances the cursor and completes when there are no more records' do
      stub_find_messages([])

      importer.import_batch!

      expect(channel.reload.provider_config['import_status']).to eq('completed')
    end
  end
end
