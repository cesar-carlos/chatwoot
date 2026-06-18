require 'rails_helper'

RSpec.describe Tiktok::MessageService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_tiktok, account: account, business_id: 'biz-123') }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: 'tt-conv-1') }

  let(:tiktok_client) { instance_double(Tiktok::Client, image_send_capable?: false) }

  before do
    allow(Tiktok::Client).to receive(:new).and_return(tiktok_client)
  end

  describe '#perform' do
    def incoming_text_content(message_id: 'tt-msg-1')
      {
        type: 'text',
        message_id: message_id,
        timestamp: 1_700_000_000_000,
        conversation_id: 'tt-conv-1',
        text: { body: 'Hello from TikTok' },
        from: 'Alice',
        from_user: { id: 'user-1' },
        to: 'Biz',
        to_user: { id: 'biz-123' }
      }.deep_symbolize_keys
    end

    it 'creates an incoming text message' do
      content = incoming_text_content

      expect do
        service = described_class.new(channel: channel, content: content)
        allow(service).to receive(:create_contact_inbox).and_return(contact_inbox)
        service.perform
      end.to change(Message, :count).by(1)

      message = Message.last
      expect(message.inbox).to eq(inbox)
      expect(message.message_type).to eq('incoming')
      expect(message.content).to eq('Hello from TikTok')
      expect(message.source_id).to eq('tt-msg-1')
      expect(message.sender).to eq(contact)
      expect(message.content_attributes['is_unsupported']).to be_nil
    end

    context 'when conversation thread mode changes by inbox setting' do
      let!(:resolved_conversation) do
        create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)
      end

      it 'creates a new conversation when lock_to_single_conversation is disabled' do
        inbox.update!(lock_to_single_conversation: false)

        service = described_class.new(channel: channel, content: incoming_text_content(message_id: 'tt-msg-off'))
        allow(service).to receive(:create_contact_inbox).and_return(contact_inbox)

        expect { service.perform }.to change(Conversation, :count).by(1)
        expect(Message.last.conversation_id).not_to eq(resolved_conversation.id)
      end

      it 'reuses and reopens resolved conversation when lock_to_single_conversation is enabled' do
        inbox.update!(lock_to_single_conversation: true)

        service = described_class.new(channel: channel, content: incoming_text_content(message_id: 'tt-msg-on'))
        allow(service).to receive(:create_contact_inbox).and_return(contact_inbox)

        expect { service.perform }.not_to change(Conversation, :count)
        expect(Message.last.conversation_id).to eq(resolved_conversation.id)
        expect(resolved_conversation.reload.status).to eq('open')
      end
    end

    it 'creates an incoming unsupported message for non-supported types' do
      content = {
        type: 'sticker',
        message_id: 'tt-msg-2',
        timestamp: 1_700_000_000_000,
        conversation_id: 'tt-conv-1',
        from: 'Alice',
        from_user: { id: 'user-1' },
        to: 'Biz',
        to_user: { id: 'biz-123' }
      }.deep_symbolize_keys

      service = described_class.new(channel: channel, content: content)
      allow(service).to receive(:create_contact_inbox).and_return(contact_inbox)
      service.perform

      message = Message.last
      expect(message.content).to be_nil
      expect(message.content_attributes['is_unsupported']).to be true
    end

    it 'creates an incoming embed attachment for share_post messages' do
      content = {
        type: 'share_post',
        message_id: 'tt-msg-3',
        timestamp: 1_700_000_000_000,
        conversation_id: 'tt-conv-1',
        share_post: { embed_url: 'https://www.tiktok.com/embed/123' },
        from: 'Alice',
        from_user: { id: 'user-1' },
        to: 'Biz',
        to_user: { id: 'biz-123' }
      }.deep_symbolize_keys

      service = described_class.new(channel: channel, content: content)
      allow(service).to receive(:create_contact_inbox).and_return(contact_inbox)
      service.perform

      message = Message.last
      expect(message.attachments.count).to eq(1)
      attachment = message.attachments.last
      expect(attachment.file_type).to eq('embed')
      expect(attachment.external_url).to eq('https://www.tiktok.com/embed/123')
    end

    it 'creates an incoming image attachment when media is present' do
      content = {
        type: 'image',
        message_id: 'tt-msg-4',
        timestamp: 1_700_000_000_000,
        conversation_id: 'tt-conv-1',
        image: { media_id: 'media-1' },
        from: 'Alice',
        from_user: { id: 'user-1' },
        to: 'Biz',
        to_user: { id: 'biz-123' }
      }.deep_symbolize_keys

      tempfile = Tempfile.new(['tiktok', '.png'])
      tempfile.write('fake-image')
      tempfile.rewind
      tempfile.define_singleton_method(:original_filename) { 'tiktok.png' }
      tempfile.define_singleton_method(:content_type) { 'image/png' }

      service = described_class.new(channel: channel, content: content)
      allow(service).to receive(:create_contact_inbox).and_return(contact_inbox)
      allow(service).to receive(:fetch_attachment).and_return(tempfile)

      service.perform

      message = Message.last
      expect(message.attachments.count).to eq(1)
      expect(message.attachments.last.file_type).to eq('image')
      expect(message.attachments.last.file).to be_attached
    ensure
      tempfile.close!
    end
  end
end
