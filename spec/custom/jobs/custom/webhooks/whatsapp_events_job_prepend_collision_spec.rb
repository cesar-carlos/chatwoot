# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Evolution Go vs Evolution node job prepend collision' do
  let(:account) { create(:account) }
  let(:go_channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_name' => 'shared-name',
        'instance_token' => 'go-token'
      )
    )
  end
  let(:node_channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'instance_name' => 'shared-name',
        'api_key' => 'node-key'
      )
    )
  end
  let(:go_inbox) { create(:inbox, account: account, channel: go_channel) }
  let(:node_inbox) { create(:inbox, account: account, channel: node_channel) }

  before do
    go_inbox
    node_inbox
  end

  it 'routes Go envelopes via evolution_go_instance_name, not the node prepend' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_inbound.json').read)
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'shared-name',
      'channel_id' => go_channel.id,
      'instance' => 'shared-name'
    )

    expect(Custom::Whatsapp::Evolution::WebhookDispatcher).not_to receive(:new)

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.to change(Message, :count).by(1)
  end
end
