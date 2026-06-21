# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channel::Whatsapp, type: :model do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'base_url' => 'http://localhost:8080',
        'instance_name' => 'audit-instance',
        'api_key' => 'TEST-INSTANCE-API-KEY'
      )
    )
  end

  describe '#validate_provider_config' do
    it 'skips remote credential check when only chatwoot-only settings change' do
      provider_service = instance_double(Custom::Whatsapp::Providers::EvolutionService)
      allow(channel).to receive(:provider_service).and_return(provider_service)
      expect(provider_service).not_to receive(:validate_provider_config?)

      channel.assign_attributes(provider_config: channel.provider_config.merge('sign_msg' => true))
      channel.valid?
    end
  end
end
