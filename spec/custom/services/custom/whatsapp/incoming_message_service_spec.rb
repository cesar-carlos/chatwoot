# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::IncomingMessageService do
  def load_fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/evolution/#{name}.json").read).with_indifferent_access
  end

  def evolution_inbound_params(message_id:, wa_id: '5566996971841', body: 'Oi', inbox: self.inbox)
    params = load_fixture('messages_upsert_text_normalized')
    params[:messages].first[:id] = message_id
    params[:messages].first[:from] = wa_id
    params[:contacts].first[:wa_id] = wa_id
    params[:messages].first[:text][:body] = body
    params[:phone_number] = inbox.channel.phone_number
    params
  end

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

  after do
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') do |key|
      Redis::Alfred.delete(key)
    end
  end

  describe 'Evolution conversation_pending inbound' do
    let(:pending_channel) do
      create(
        :channel_whatsapp,
        account: account,
        provider: 'evolution',
        sync_templates: false,
        validate_provider_config: false,
        provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
          'instance_name' => 'pending-instance',
          'api_key' => 'TEST-KEY',
          'conversation_pending' => true
        )
      )
    end
    let(:pending_inbox) do
      pending_channel.inbox.tap { |record| record.update!(lock_to_single_conversation: true) }
    end

    it 'creates a new conversation as pending' do
      params = evolution_inbound_params(message_id: 'EVO-PENDING-NEW-1', inbox: pending_inbox)

      expect do
        described_class.new(inbox: pending_inbox, params: params).perform
      end.to change(Conversation, :count).by(1)

      conversation = Conversation.last
      expect(conversation.inbox).to eq(pending_inbox)
      expect(conversation).to be_pending
      expect(conversation.additional_attributes['evolution_pending_since']).to be_present
    end

    it 'reopens a resolved conversation as pending' do
      contact = create(:contact, account: account, phone_number: '+5566996971841')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: pending_inbox, source_id: '5566996971841')
      resolved_conversation = create(
        :conversation,
        account: account,
        inbox: pending_inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :resolved
      )
      params = evolution_inbound_params(message_id: 'EVO-PENDING-REOPEN-1', inbox: pending_inbox)

      expect do
        described_class.new(inbox: pending_inbox, params: params).perform
      end.not_to change(Conversation, :count)

      expect(resolved_conversation.reload).to be_pending
      expect(resolved_conversation.additional_attributes['evolution_pending_since']).to be_present
    end

    it 'opens the conversation on the second customer message' do
      contact = create(:contact, account: account, phone_number: '+5566996971842')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: pending_inbox, source_id: '5566996971842')
      pending_conversation = create(
        :conversation,
        account: account,
        inbox: pending_inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :pending,
        additional_attributes: { evolution_pending_since: 1.hour.ago.utc.iso8601(3) }
      )
      create(
        :message,
        account: account,
        inbox: pending_inbox,
        conversation: pending_conversation,
        message_type: :incoming,
        source_id: 'EVO-PENDING-FIRST'
      )
      params = evolution_inbound_params(
        message_id: 'EVO-PENDING-SECOND-1',
        wa_id: '5566996971842',
        body: 'Second message',
        inbox: pending_inbox
      )

      described_class.new(inbox: pending_inbox, params: params).perform

      expect(pending_conversation.reload).to be_open
      expect(pending_conversation.additional_attributes['evolution_pending_since']).to be_blank
    end
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

    it 'defers status update when the message is not found yet' do
      allow(Rails.logger).to receive(:info)

      expect do
        described_class.new(
          inbox: inbox,
          params: {
            statuses: [{ id: 'MISSING_ID', status: 'read', timestamp: Time.current.to_i.to_s, recipient_id: '5511999999999' }],
            phone_number: channel.phone_number
          }
        ).perform
      end.to have_enqueued_job(Custom::Whatsapp::Evolution::DeferredStatusJob)

      expect(Rails.logger).to have_received(:info).with(
        '[EVOLUTION] status update deferred source_id=MISSING_ID status=read'
      )
    end
  end
end
