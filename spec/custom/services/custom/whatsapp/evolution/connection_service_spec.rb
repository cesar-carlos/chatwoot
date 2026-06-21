# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::ConnectionService do
  subject(:service) { described_class.new(channel: channel) }

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
        'proxy_enabled' => false
      )
    )
  end

  describe '#proxy_payload' do
    it 'returns enabled false when proxy_enabled is false' do
      expect(service.send(:proxy_payload)).to eq(enabled: false)
    end
  end

  describe '#provision_new_instance!' do
    let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }

    before do
      allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:new).and_return(api_client)
    end

    it 'deletes the remote instance when post-create provisioning fails' do
      create_response = instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'hash' => 'instance-key', 'instance' => { 'instanceId' => 'id-1', 'status' => 'connecting' } }
      )
      webhook_response = instance_double(HTTParty::Response, success?: false, code: 500, parsed_response: { 'message' => 'fail' })
      delete_response = instance_double(HTTParty::Response, success?: true)

      allow(api_client).to receive(:create_instance).and_return(create_response)
      allow(api_client).to receive(:apply_webhook).and_return(webhook_response)
      allow(api_client).to receive(:delete_instance).and_return(delete_response)

      expect do
        service.provision_new_instance!
      end.to raise_error(Custom::Whatsapp::Evolution::ApiError)

      expect(api_client).to have_received(:delete_instance)
    end
  end

  describe '#update_runtime_config!' do
    it 'persists runtime fields without triggering save callbacks' do
      expect(channel).not_to receive(:save!)

      service.send(:update_runtime_config!, 'connection_status' => 'open')

      channel.reload
      expect(channel.provider_config['connection_status']).to eq('open')
    end
  end
end
