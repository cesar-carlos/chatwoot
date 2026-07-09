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
end
