# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::Import::MessagesImporter do
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
        'instance_token' => 'token',
        'import_messages' => true,
        'days_limit_import_messages' => 7
      )
    )
  end
  let(:runtime) { Custom::Whatsapp::EvolutionGo::Import::Runtime.new(channel: channel) }
  let(:api_client) { instance_double(Custom::Whatsapp::EvolutionGo::ApiClient) }
  let(:importer) { described_class.new(runtime: runtime, api_client: api_client) }

  before do
    key = format(Redis::RedisKeys::EVOLUTION_GO_IMPORT_REMOTE_JIDS, channel_id: channel.id)
    Redis::Alfred.set(key, ['5511999999999@s.whatsapp.net'].to_json)
    runtime.persist_cursor!('message_jid_index' => 0, 'phase' => 'messages')
  end

  it 'sends days_limit_import_messages as history-sync count (not a day window)' do
    response = instance_double(HTTParty::Response, success?: true)
    expect(api_client).to receive(:history_sync).with(
      chat: '5511999999999@s.whatsapp.net',
      count: 7
    ).and_return(response)
    expect(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:raise_unless_success!).with(
      response,
      'Failed to request Evolution Go history sync'
    )

    importer.import_batch!
  end

  it 'defaults count to 100 when the config key is missing' do
    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      provider_config: channel.provider_config.except('days_limit_import_messages')
    )
    channel.provider_config = channel.provider_config.except('days_limit_import_messages')
    runtime = Custom::Whatsapp::EvolutionGo::Import::Runtime.new(channel: channel.reload)
    importer = described_class.new(runtime: runtime, api_client: api_client)

    response = instance_double(HTTParty::Response, success?: true)
    expect(api_client).to receive(:history_sync).with(
      chat: '5511999999999@s.whatsapp.net',
      count: 100
    ).and_return(response)
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:raise_unless_success!)

    importer.import_batch!
  end
end
