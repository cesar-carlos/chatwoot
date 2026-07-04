# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::Import::Runtime do
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
        'import_contacts' => true,
        'import_status' => 'failed',
        'import_failed_at' => 1.hour.ago.iso8601,
        'import_error' => 'previous failure'
      )
    )
  end
  let(:runtime) { described_class.new(channel: channel) }

  before { create(:inbox, account: account, channel: channel) }

  describe '#mark_running!' do
    it 'clears import_failed_at when resuming import' do
      runtime.mark_running!

      channel.reload
      expect(channel.provider_config['import_status']).to eq('running')
      expect(channel.provider_config['import_failed_at']).to be_nil
      expect(channel.provider_config['import_error']).to be_nil
    end
  end

  describe '#mark_failed!' do
    it 'records import_failed_at without setting import_completed_at' do
      runtime.mark_failed!(StandardError.new('boom'))

      channel.reload
      expect(channel.provider_config['import_status']).to eq('failed')
      expect(channel.provider_config['import_failed_at']).to be_present
      expect(channel.provider_config['import_completed_at']).to be_nil
    end
  end

  describe '#import_stale?' do
    it 'is false when the import is not running' do
      expect(runtime.import_stale?).to be false
    end

    it 'is false for a running import with a recent heartbeat' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'import_status' => 'running',
          'import_heartbeat_at' => 1.minute.ago.iso8601
        )
      )

      expect(described_class.new(channel: channel.reload).import_stale?).to be false
    end

    it 'is true for a running import whose heartbeat is older than the stale threshold' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'import_status' => 'running',
          'import_heartbeat_at' => (described_class::STALE_RUNNING_AFTER + 1.minute).ago.iso8601
        )
      )

      expect(described_class.new(channel: channel.reload).import_stale?).to be true
    end

    it 'falls back to import_started_at when there is no heartbeat yet' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'import_status' => 'running',
          'import_started_at' => (described_class::STALE_RUNNING_AFTER + 1.minute).ago.iso8601,
          'import_heartbeat_at' => nil
        )
      )

      expect(described_class.new(channel: channel.reload).import_stale?).to be true
    end

    it 'is true when running with no timestamp at all (defensive default)' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'import_status' => 'running',
          'import_started_at' => nil,
          'import_heartbeat_at' => nil
        )
      )

      expect(described_class.new(channel: channel.reload).import_stale?).to be true
    end
  end

  describe '#touch_heartbeat!' do
    it 'persists a fresh import_heartbeat_at timestamp' do
      runtime.touch_heartbeat!

      channel.reload
      expect(Time.zone.parse(channel.provider_config['import_heartbeat_at'])).to be_within(5.seconds).of(Time.current)
    end
  end
end
