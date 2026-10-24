# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::SettingsSync do
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
        'instance_id' => 'instance-1'
      ).except('ignore_groups', 'ignore_status')
    )
  end

  it 'sends default-on booleans when the keys are missing' do
    payload = Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: channel)
                                                              .send(:advanced_settings_payload)

    expect(payload[:ignoreGroups]).to be(true)
    expect(payload[:ignoreStatus]).to be(true)
    expect(payload[:rejectCall]).to be(false)
  end
end
