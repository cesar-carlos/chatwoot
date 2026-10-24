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

  it 'resumes a running import when the worker lock is free' do
    channel.update!(
      provider_config: channel.provider_config.merge(
        'import_contacts' => false,
        'import_messages' => true,
        'import_status' => 'running',
        'import_heartbeat_at' => Time.current.iso8601,
        'import_cursor' => { 'phase' => 'messages', 'message_jid_index' => 1 }
      )
    )
    importer = instance_double(Custom::Whatsapp::EvolutionGo::Import::MessagesImporter, import_batch!: true)
    allow(Custom::Whatsapp::EvolutionGo::Import::MessagesImporter).to receive(:new).and_return(importer)
    allow(Custom::Whatsapp::EvolutionGo::ImportJob).to receive(:set).and_return(Custom::Whatsapp::EvolutionGo::ImportJob)
    allow(Custom::Whatsapp::EvolutionGo::ImportJob).to receive(:perform_later)

    described_class.new(channel: channel.reload, force: false).perform

    expect(importer).to have_received(:import_batch!).exactly(5).times
  end

  it 'does not start work while another import worker holds the lock' do
    channel.update!(
      provider_config: channel.provider_config.merge(
        'import_contacts' => false,
        'import_messages' => true,
        'import_status' => 'running',
        'import_heartbeat_at' => Time.current.iso8601
      )
    )
    allow(Redis::Alfred).to receive(:set).and_return(false)
    allow(Custom::Whatsapp::EvolutionGo::Import::MessagesImporter).to receive(:new)

    described_class.new(channel: channel.reload, force: false).perform

    expect(Custom::Whatsapp::EvolutionGo::Import::MessagesImporter).not_to have_received(:new)
  end
end
