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
  let(:inbox) { create(:inbox, account: account, channel: channel) }
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

    it 'advances the cursor and completes when there are no more records' do
      stub_find_messages([])

      importer.import_batch!

      expect(channel.reload.provider_config['import_status']).to eq('completed')
    end
  end
end
