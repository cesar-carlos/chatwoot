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
end
