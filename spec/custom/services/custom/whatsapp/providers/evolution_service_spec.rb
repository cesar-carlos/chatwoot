# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Providers::EvolutionService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'base_url' => 'http://localhost:8080',
        'instance_name' => 'test-instance',
        'api_key' => 'TEST-KEY'
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999999999') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:service) { described_class.new(whatsapp_channel: channel) }
  let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }

  before do
    allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:for_channel).with(channel).and_return(api_client)
  end

  describe '#validate_provider_config?' do
    it 'returns true when connection state is open' do
      response = instance_double(HTTParty::Response, success?: true, parsed_response: { 'instance' => { 'state' => 'open' } })
      allow(api_client).to receive(:connection_state).and_return(response)

      expect(service.validate_provider_config?).to be(true)
    end

    it 'returns false when connection state is close' do
      response = instance_double(HTTParty::Response, success?: true, parsed_response: { 'instance' => { 'state' => 'close' } })
      allow(api_client).to receive(:connection_state).and_return(response)

      expect(service.validate_provider_config?).to be(false)
    end
  end

  describe '#build_quoted_context' do
    let(:user) { create(:user, account: account) }

    it 'sets fromMe true when replying to an outbound message' do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: user,
        source_id: 'OUT123',
        content: 'Previous reply'
      )
      message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: user,
        content_attributes: { in_reply_to_external_id: 'OUT123' }
      )

      quoted = service.send(:build_quoted_context, '5511999999999', message)

      expect(quoted.dig(:key, :fromMe)).to be(true)
      expect(quoted.dig(:message, :conversation)).to eq('Previous reply')
    end

    it 'sets fromMe false when replying to an incoming message' do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        sender: contact,
        source_id: 'IN123',
        content: 'Customer message',
        content_attributes: { evolution_remote_jid: '5511999999999@s.whatsapp.net' }
      )
      message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: user,
        content_attributes: { in_reply_to_external_id: 'IN123' }
      )

      quoted = service.send(:build_quoted_context, '5511999999999', message)

      expect(quoted.dig(:key, :fromMe)).to be(false)
      expect(quoted.dig(:key, :remoteJid)).to eq('5511999999999@s.whatsapp.net')
    end

    it 'scopes quoted lookup to the current conversation' do
      other_contact = create(:contact, account: account, phone_number: '+5511888888888')
      other_contact_inbox = create(:contact_inbox, contact: other_contact, inbox: inbox, source_id: '5511888888888')
      other_conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: other_contact,
        contact_inbox: other_contact_inbox
      )
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: other_conversation,
        message_type: :incoming,
        sender: other_contact,
        source_id: 'SHARED-ID',
        content: 'Wrong conversation'
      )
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        sender: contact,
        source_id: 'SHARED-ID',
        content: 'Right conversation',
        content_attributes: { evolution_remote_jid: '5511999999999@s.whatsapp.net' }
      )
      message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: user,
        content_attributes: { in_reply_to_external_id: 'SHARED-ID' }
      )

      quoted = service.send(:build_quoted_context, '5511999999999', message)

      expect(quoted.dig(:message, :conversation)).to eq('Right conversation')
    end
  end

  describe '#process_response' do
    let(:user) { create(:user, account: account) }
    let(:message) do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: user,
        content: 'Hello'
      )
    end

    it 'returns source_id from a successful response' do
      response = instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'key' => { 'id' => 'EVO-MSG-123' } }
      )

      expect(service.process_response(response, message)).to eq('EVO-MSG-123')
    end

    it 'returns nil and marks the message failed on error' do
      response = instance_double(
        HTTParty::Response,
        success?: false,
        parsed_response: { 'message' => 'send failed' },
        code: 400,
        body: 'send failed'
      )

      expect(service.process_response(response, message)).to be_nil
      expect(message.reload.status).to eq('failed')
    end
  end

  describe 'mark_read_on_reply' do
    let(:user) { create(:user, account: account) }
    let!(:incoming_message) do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        sender: contact,
        source_id: 'IN-LAST',
        status: :delivered,
        content: 'Customer question',
        content_attributes: { evolution_remote_jid: '5511999999999@s.whatsapp.net' }
      )
    end
    let(:outgoing_message) do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: user,
        content: 'Agent reply'
      )
    end
    let(:success_response) do
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'key' => { 'id' => 'OUT-123' } }
      )
    end

    before do
      channel.update!(provider_config: channel.provider_config.merge('mark_read_on_reply' => true))
      allow(api_client).to receive(:send_text).and_return(success_response)
      allow(api_client).to receive(:mark_message_as_read).and_return(success_response)
    end

    it 'marks the last incoming message as read after a successful send' do
      service.send(:send_text_message, '5511999999999', outgoing_message)

      expect(api_client).to have_received(:mark_message_as_read).with(
        read_messages: [
          {
            id: incoming_message.source_id,
            fromMe: false,
            remoteJid: '5511999999999@s.whatsapp.net'
          }
        ]
      )
    end

    it 'does not mark read when mark_read_on_reply is disabled' do
      channel.update!(provider_config: channel.provider_config.merge('mark_read_on_reply' => false))

      service.send(:send_text_message, '5511999999999', outgoing_message)

      expect(api_client).not_to have_received(:mark_message_as_read)
    end

    it 'marks the replied-to incoming message as read when in_reply_to_external_id is set' do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        sender: contact,
        source_id: 'IN-OLDER',
        status: :read,
        content: 'Older message',
        created_at: 2.hours.ago,
        content_attributes: { evolution_remote_jid: '5511999999999@s.whatsapp.net' }
      )
      reply_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: user,
        content: 'Quoted reply',
        content_attributes: { in_reply_to_external_id: 'IN-OLDER' }
      )

      service.send(:send_text_message, '5511999999999', reply_message)

      expect(api_client).to have_received(:mark_message_as_read).with(
        read_messages: [
          {
            id: 'IN-OLDER',
            fromMe: false,
            remoteJid: '5511999999999@s.whatsapp.net'
          }
        ]
      )
    end
  end

  describe '#send_message with contact attachment' do
    let(:user) { create(:user, account: account) }
    let(:contact_message) do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: user,
        content: nil
      )
    end
    let(:contact_response) do
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'key' => { 'id' => 'CONTACT123' } })
    end

    before do
      contact_message.attachments.create!(
        account_id: account.id,
        file_type: :contact,
        fallback_title: '+5511888888888',
        meta: { firstName: 'Jane', lastName: 'Doe', companyName: 'Acme' }
      )
      allow(api_client).to receive(:send_contact).and_return(contact_response)
      allow(api_client).to receive(:mark_message_as_read)
    end

    it 'sends contact via Evolution sendContact endpoint' do
      expect(service.send_message('5511999999999', contact_message)).to eq('CONTACT123')
      expect(api_client).to have_received(:send_contact).with(
        hash_including(
          number: '5511999999999',
          contact: [
            hash_including(
              fullName: 'Jane Doe',
              wuid: '5511888888888',
              phoneNumber: '5511888888888',
              organization: 'Acme'
            )
          ]
        )
      )
    end
  end
end
