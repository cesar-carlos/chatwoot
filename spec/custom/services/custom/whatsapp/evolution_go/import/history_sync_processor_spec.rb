# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::Import::HistorySyncProcessor do
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
        'import_messages' => true
      )
    )
  end
  let(:record) do
    {
      'key' => {
        'remoteJid' => '5511999999999@s.whatsapp.net',
        'fromMe' => false,
        'id' => 'HIST-1'
      },
      'message' => { 'conversation' => 'hello from history' },
      'messageTimestamp' => Time.now.to_i
    }
  end

  def imported_count
    channel.reload.provider_config.dig('import_stats', 'messages_imported').to_i
  end

  it 'does not count a record that was not stored' do
    allow(Custom::Whatsapp::EvolutionGo::InboundMessageProcessor).to receive(:process)

    described_class.new(channel: channel, data: { 'messages' => [record] }).perform

    expect(channel.inbox.messages.find_by(source_id: 'HIST-1')).to be_blank
    expect(imported_count).to eq(0)
  end

  it 'raises when the inbound dedup lock is busy so the webhook job can retry' do
    allow(Custom::Whatsapp::EvolutionGo::InboundMessageProcessor).to receive(:process)
      .and_raise(MutexApplicationJob::LockAcquisitionError)

    expect do
      described_class.new(channel: channel, data: { 'messages' => [record] }).perform
    end.to raise_error(MutexApplicationJob::LockAcquisitionError)
    expect(imported_count).to eq(0)
  end

  it 'counts a record that was stored' do
    described_class.new(channel: channel, data: { 'messages' => [record] }).perform

    expect(channel.inbox.messages.find_by(source_id: 'HIST-1')).to be_present
    expect(imported_count).to eq(1)
  end
end
