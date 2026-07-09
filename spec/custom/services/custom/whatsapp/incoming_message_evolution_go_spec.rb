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
end
