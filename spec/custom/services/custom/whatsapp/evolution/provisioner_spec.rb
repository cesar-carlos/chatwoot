# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::Provisioner do
  subject(:provisioner) do
    described_class.new(channel: channel, connection_service: connection_service)
  end

  let(:account) { create(:account) }
  let(:connection_service) { Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'base_url' => 'http://localhost:8080',
        'instance_name' => 'provision-test',
        'api_key' => 'GLOBAL-API-KEY',
        'webhook_token' => 'secure-webhook-token',
        'groups_ignore' => true,
        'reject_call' => false,
        'proxy_enabled' => false
      )
    )
  end
  let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }
  let(:create_response) do
    instance_double(
      HTTParty::Response,
      success?: true,
      parsed_response: JSON.parse(
        Rails.root.join('spec/fixtures/evolution/instance_create_response.json').read
      )
    )
  end
  let(:success_response) { instance_double(HTTParty::Response, success?: true, parsed_response: {}) }

  before do
    allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:for_channel).and_return(api_client)
    allow(connection_service).to receive(:fetch_qr_code)
  end

  describe '#provision_new_instance!' do
    around do |example|
      with_modified_env FRONTEND_URL: 'https://chatwoot.example.com', &example
    end

    it 'creates the instance and runs post-create provisioning' do
      allow(api_client).to receive_messages(
        create_instance: create_response,
        apply_webhook: success_response,
        apply_settings: success_response,
        disable_chatwoot_integration: success_response,
        find_chatwoot_integration: instance_double(
          HTTParty::Response,
          success?: true,
          parsed_response: { 'enabled' => false }
        )
      )

      provisioner.provision_new_instance!

      expect(api_client).to have_received(:create_instance).with(
        hash_including(
          instanceName: 'provision-test',
          integration: 'WHATSAPP-BAILEYS',
          qrcode: true,
          groupsIgnore: true
        )
      )
      expect(api_client).to have_received(:apply_webhook).with(
        'https://chatwoot.example.com/webhooks/evolution/provision-test?token=secure-webhook-token'
      )
      expect(api_client).to have_received(:apply_settings)
      expect(api_client).to have_received(:disable_chatwoot_integration)
      expect(connection_service).to have_received(:fetch_qr_code)
      expect(channel.reload.provider_config['api_key']).to eq('A00CE258-1BE7-49D9-89BB-1829C69724DE')
      expect(channel.provider_config['connection_status']).to eq('connecting')
    end

    it 'rolls back the remote instance when webhook registration fails' do
      rollback_connection_service = instance_double(Custom::Whatsapp::Evolution::ConnectionService)
      rollback_provisioner = described_class.new(channel: channel, connection_service: rollback_connection_service)
      allow(rollback_connection_service).to receive(:send)

      webhook_failure = instance_double(
        HTTParty::Response,
        success?: false,
        code: 500,
        parsed_response: { 'message' => 'webhook failed' }
      )
      delete_response = instance_double(HTTParty::Response, success?: true)

      allow(api_client).to receive_messages(
        create_instance: create_response,
        apply_webhook: webhook_failure,
        delete_instance: delete_response
      )

      expect do
        rollback_provisioner.provision_new_instance!
      end.to raise_error(Custom::Whatsapp::Evolution::ApiError, /Failed to register Evolution webhook/)

      expect(api_client).to have_received(:delete_instance)
    end

    it 'does not delete the remote instance when create fails' do
      create_failure = instance_double(
        HTTParty::Response,
        success?: false,
        code: 400,
        parsed_response: { 'message' => 'duplicate instance' }
      )

      allow(api_client).to receive(:create_instance).and_return(create_failure)
      allow(api_client).to receive(:delete_instance)

      expect do
        provisioner.provision_new_instance!
      end.to raise_error(Custom::Whatsapp::Evolution::ApiError)

      expect(api_client).not_to have_received(:delete_instance)
    end

    it 'raises when FRONTEND_URL is missing' do
      with_modified_env FRONTEND_URL: nil do
        expect do
          provisioner.provision_new_instance!
        end.to raise_error(
          Custom::Whatsapp::Evolution::ApiError,
          /FRONTEND_URL is not configured/
        )
      end
    end
  end

  describe '#provision_post_create!' do
    around do |example|
      with_modified_env FRONTEND_URL: 'https://chatwoot.example.com', &example
    end

    it 'syncs proxy when enabled' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'proxy_enabled' => true,
          'proxy_host' => 'proxy.example.com',
          'proxy_port' => '8080',
          'proxy_protocol' => 'http'
        )
      )
      channel.reload
      allow(api_client).to receive_messages(
        apply_webhook: success_response,
        apply_settings: success_response,
        apply_proxy: success_response,
        disable_chatwoot_integration: success_response,
        find_chatwoot_integration: instance_double(
          HTTParty::Response,
          success?: true,
          parsed_response: { 'enabled' => false }
        )
      )

      provisioner.provision_post_create!(create_response.parsed_response)

      expect(api_client).to have_received(:apply_proxy).with(
        hash_including(
          enabled: true,
          host: 'proxy.example.com',
          port: '8080',
          protocol: 'http'
        )
      )
    end
  end

  describe '#ensure_chatwoot_integration_disabled!' do
    it 'raises when Evolution Chatwoot integration remains enabled' do
      allow(api_client).to receive_messages(
        disable_chatwoot_integration: success_response,
        find_chatwoot_integration: instance_double(
          HTTParty::Response,
          success?: true,
          parsed_response: { 'enabled' => true }
        )
      )

      expect do
        provisioner.ensure_chatwoot_integration_disabled!
      end.to raise_error(
        Custom::Whatsapp::Evolution::ApiError,
        /Evolution Chatwoot integration is still enabled/
      )
    end
  end

  describe '#delete_remote_instance!' do
    it 'logs a warning when delete fails' do
      allow(api_client).to receive(:delete_instance).and_return(
        instance_double(HTTParty::Response, success?: false, code: 500)
      )
      allow(Rails.logger).to receive(:warn)

      provisioner.delete_remote_instance!

      expect(Rails.logger).to have_received(:warn).with(
        '[EVOLUTION] failed to delete instance provision-test: HTTP 500'
      )
    end
  end
end
