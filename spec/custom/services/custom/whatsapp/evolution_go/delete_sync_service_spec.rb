# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::DeleteSyncService do
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
        'instance_token' => 'TEST-TOKEN',
        'base_url' => 'https://evogo.example.com',
        'sync_delete_to_whatsapp' => true
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
      source_id: 'OUT-MSG-1',
      content: 'hello',
      content_attributes: { evolution_go_remote_jid: '5511999999999@s.whatsapp.net' }
    )
  end
  let(:api_client) { instance_double(Custom::Whatsapp::EvolutionGo::ApiClient) }
  let(:response) { instance_double(HTTParty::Response, success?: true, code: 200) }

  before do
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).with(channel).and_return(api_client)
  end

  it 'calls Evolution Go delete API when enabled' do
    expect(api_client).to receive(:delete_message).with(
      chat: '5511999999999@s.whatsapp.net',
      message_id: 'OUT-MSG-1'
    ).and_return(response)

    described_class.new(message: message).perform
  end

  it 'skips when sync_delete_to_whatsapp is disabled' do
    channel.update!(
      provider_config: channel.provider_config.merge('sync_delete_to_whatsapp' => false)
    )

    expect(api_client).not_to receive(:delete_message)

    described_class.new(message: message).perform
  end
end
