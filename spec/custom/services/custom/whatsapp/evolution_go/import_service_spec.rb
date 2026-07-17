# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::ImportService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_name' => 'test-go-import',
        'instance_token' => 'token',
        'import_contacts' => false,
        'import_messages' => false,
        'import_status' => 'running',
        'import_cursor' => { 'phase' => 'contacts', 'contacts_offset' => 250 },
        'import_stats' => { 'contacts_imported' => 250 },
        'import_heartbeat_at' => 3.days.ago.iso8601
      )
    )
  end

  before do
    allow(Redis::Alfred).to receive(:set).and_return(true)
    allow(Redis::Alfred).to receive(:delete)
  end

  it 'clears stuck running status when import toggles are disabled' do
    described_class.new(channel: channel, force: false).perform

    config = channel.reload.provider_config
    expect(config['import_status']).to eq('idle')
    expect(config.dig('import_cursor', 'phase')).to eq('done')
  end
end
