# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channel::Whatsapp do
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
        'api_key' => 'TEST-INSTANCE-API-KEY',
        'webhook_token' => 'super-secret-webhook-token',
        'proxy_password' => 'super-secret-proxy-password'
      )
    )
  end

  describe '#dashboard_provider_config' do
    it 'masks api_key, proxy_password and webhook_token for evolution channels' do
      config = channel.dashboard_provider_config

      expect(config['api_key']).to eq('••••••••')
      expect(config['proxy_password']).to eq('••••••••')
      expect(config['webhook_token']).to eq('••••••••')
      expect(config['instance_name']).to eq('test-instance')
    end

    it 'does not mask anything for non-evolution channels' do
      cloud_channel = create(
        :channel_whatsapp,
        account: account,
        provider: 'whatsapp_cloud',
        sync_templates: false,
        validate_provider_config: false
      )

      expect(cloud_channel.dashboard_provider_config).to eq(cloud_channel.provider_config)
    end
  end

  describe '#provider_service' do
    it 'raises loudly instead of silently falling back to 360dialog when the registry has no evolution entry' do
      allow(MessagingProvider::Registry).to receive(:resolve).with('evolution', anything).and_return(nil)

      expect { channel.provider_service }.to raise_error(/MessagingProvider::Registry has no service registered/)
    end
  end

  describe '#sync_evolution_provider_to_api (settings_sync_error handling)' do
    let(:connection_service) { instance_double(Custom::Whatsapp::Evolution::ConnectionService) }

    before do
      allow(Custom::Whatsapp::Evolution::ConnectionService).to receive(:new).and_return(connection_service)
    end

    it 'does not call the Evolution API and does not touch settings_sync_error for unrelated config changes' do
      channel.update_column(:provider_config, channel.provider_config.merge('settings_sync_error' => 'stale error')) # rubocop:disable Rails/SkipsModelValidations
      channel.reload

      channel.update!(provider_config: channel.provider_config.merge('sign_msg' => true))

      expect(Custom::Whatsapp::Evolution::ConnectionService).not_to have_received(:new)
      expect(channel.reload.provider_config['settings_sync_error']).to eq('stale error')
    end

    it 'syncs settings and clears a previous error when a syncable key changes' do
      allow(connection_service).to receive(:sync_settings!)
      channel.update_column(:provider_config, channel.provider_config.merge('settings_sync_error' => 'stale error')) # rubocop:disable Rails/SkipsModelValidations
      channel.reload

      channel.update!(provider_config: channel.provider_config.merge('groups_ignore' => false))

      expect(connection_service).to have_received(:sync_settings!)
      expect(channel.reload.provider_config['settings_sync_error']).to be_nil
    end

    it 'records settings_sync_error and does not clear it when the sync call fails' do
      allow(connection_service).to receive(:sync_settings!).and_raise(
        Custom::Whatsapp::Evolution::ApiError.new('sync boom')
      )

      channel.update!(provider_config: channel.provider_config.merge('groups_ignore' => false))

      expect(channel.reload.provider_config['settings_sync_error']).to include('sync boom')
    end
  end
end
