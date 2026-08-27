# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::IncomingMessageEvolutionGo do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_name' => 'test-go-instance',
        'instance_token' => 'token'
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: '3EB0READRECEIPT01',
      status: :delivered
    )
  end

  it 'updates message status without calling missing super method' do
    normalized = {
      statuses: [
        {
          id: message.source_id,
          status: 'read',
          recipient_id: '5511999999999'
        }
      ]
    }

    expect do
      Whatsapp::IncomingMessageService.new(inbox: inbox, params: normalized).perform
    end.not_to raise_error

    expect(message.reload.status).to eq('read')
  end

  it 'enqueues media download after the inbound transaction commits' do
    create(:contact_inbox, inbox: inbox, source_id: '5511999999999')
    normalized = {
      contacts: [{ profile: { name: 'Alice' }, wa_id: '5511999999999' }],
      messages: [
        {
          from: '5511999999999',
          id: 'DOC-ONLY-1',
          timestamp: Time.now.to_i.to_s,
          type: 'document',
          document: {
            filename: 'anotacoes.txt',
            mimetype: 'text/plain',
            _evolution_go_message: {
              key: { id: 'DOC-ONLY-1', remoteJid: '5511999999999@s.whatsapp.net', fromMe: false },
              message: {
                base64: Base64.strict_encode64('file body'),
                documentMessage: { fileName: 'anotacoes.txt', mimetype: 'text/plain' }
              }
            }
          }
        }
      ]
    }

    expect(Custom::Whatsapp::EvolutionGo::MediaDownloadJob).to receive(:perform_later) do |channel_id, message_id, _payload, type|
      expect(channel_id).to eq(channel.id)
      expect(Message.find_by(id: message_id)).to be_present
      expect(type).to eq('document')
    end

    Whatsapp::IncomingMessageService.new(inbox: inbox, params: normalized).perform

    created = inbox.messages.find_by(source_id: 'DOC-ONLY-1')
    expect(created).to be_present
    expect(created.content).to be_blank
  end

  it 'persists group participant jid and push name on content_attributes' do
    channel.update!(
      provider_config: channel.provider_config.merge('ignore_groups' => false)
    )
    allow(Custom::Whatsapp::Evolution::GroupMetadataService).to receive(:new).and_return(
      instance_double(Custom::Whatsapp::Evolution::GroupMetadataService, display_name: 'Support Team')
    )
    allow(Custom::Whatsapp::Evolution::GroupParticipantService).to receive(:new).and_return(
      instance_double(Custom::Whatsapp::Evolution::GroupParticipantService, sync!: true)
    )

    normalized = {
      contacts: [{ profile: { name: 'Support Team' }, wa_id: '120363012345678901@g.us' }],
      messages: [
        {
          from: '120363012345678901@g.us',
          id: 'GROUP-IN-1',
          timestamp: Time.now.to_i.to_s,
          type: 'text',
          text: { body: 'Hello group' },
          evolution_go_remote_jid: '120363012345678901@g.us',
          evolution_go_participant_jid: '5511777777777@s.whatsapp.net',
          evolution_go_participant_push_name: 'Group Member'
        }
      ]
    }

    Whatsapp::IncomingMessageService.new(inbox: inbox, params: normalized).perform

    created = inbox.messages.find_by(source_id: 'GROUP-IN-1')
    aggregate_failures do
      expect(created).to be_present
      expect(created.content_attributes['evolution_go_remote_jid']).to eq('120363012345678901@g.us')
      expect(created.content_attributes['evolution_go_participant_jid']).to eq('5511777777777@s.whatsapp.net')
      expect(created.content_attributes['evolution_go_participant_push_name']).to eq('Group Member')
    end
  end

  it 'matches LID-only inbound to an existing identifier without inventing a phone number' do
    allow(Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob).to receive(:perform_later)
    lid = '149215904792765@lid'
    contact = create(:contact, account: account, identifier: lid, phone_number: '+5566999511286', name: 'Sulifran')
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566999511286')

    normalized = {
      contacts: [{ profile: { name: 'Sulifran' }, wa_id: lid }],
      messages: [
        {
          from: lid,
          id: 'LID-ONLY-IN-1',
          timestamp: Time.now.to_i.to_s,
          type: 'text',
          text: { body: 'hello lid' },
          evolution_go_remote_jid: lid
        }
      ]
    }

    expect do
      Whatsapp::IncomingMessageService.new(inbox: inbox, params: normalized).perform
    end.not_to change(Contact, :count)

    created = inbox.messages.find_by(source_id: 'LID-ONLY-IN-1')
    aggregate_failures do
      expect(created).to be_present
      expect(created.conversation.contact).to eq(contact)
      expect(created.conversation.contact.phone_number).to eq('+5566999511286')
      expect(inbox.contact_inboxes.where(contact: contact).count).to eq(1)
    end
  end

  it 'matches LID+alt inbound to an existing Brazil WITH-9 contact_inbox' do
    allow(Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob).to receive(:perform_later)
    contact = create(:contact, account: account, phone_number: '+5566996801137', name: 'Lilia')
    existing = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566996801137')

    normalized = {
      contacts: [{ profile: { name: 'Lilia' }, wa_id: '556696801137' }],
      messages: [
        {
          from: '556696801137',
          id: 'LID-ALT-IN-1',
          timestamp: Time.now.to_i.to_s,
          type: 'text',
          text: { body: 'hello from pn alt' },
          evolution_go_remote_jid: '112992117112907@lid'
        }
      ]
    }

    Whatsapp::IncomingMessageService.new(inbox: inbox, params: normalized).perform

    created = inbox.messages.find_by(source_id: 'LID-ALT-IN-1')
    aggregate_failures do
      expect(created).to be_present
      expect(created.conversation.contact_inbox).to eq(existing)
      expect(contact.reload.identifier).to eq('112992117112907@lid')
      expect(contact.additional_attributes['evolution_go_remote_jid']).to eq('112992117112907@lid')
      expect(inbox.contact_inboxes.where(contact: contact).count).to eq(1)
    end
  end
end
