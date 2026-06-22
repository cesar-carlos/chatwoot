# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::LostMessagesReconciliationService do
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
        'base_url' => 'http://localhost:8080',
        'sync_lost_messages' => true,
        'connection_status' => 'open'
      )
    )
  end
  let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }

  before do
    allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:for_channel).and_return(api_client)
    allow(api_client).to receive(:find_messages).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'messages' => {
            'records' => [],
            'pages' => 1
          }
        }
      )
    )
  end

  it 'skips reconciliation when sync_lost_messages is disabled' do
    channel.update!(
      provider_config: channel.provider_config.merge('sync_lost_messages' => false)
    )

    expect(api_client).not_to receive(:find_messages)
    described_class.new(channel: channel).perform
  end

  it 'queries Evolution when sync is enabled and connection is open' do
    expect(api_client).to receive(:find_messages).once
    described_class.new(channel: channel).perform
  end
end
