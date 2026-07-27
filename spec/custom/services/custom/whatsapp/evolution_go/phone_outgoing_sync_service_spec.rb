# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::PhoneOutgoingSyncService do
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
        'ignore_from_me_echo' => false
      )
    )
  end
  let(:inbox) { channel.inbox }

  before { inbox }

  it 'does not create a message for protocol-only revoke payloads' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_revoke_pascal_case.json').read)

    expect do
      described_class.new(channel: channel, data: payload['data']).perform
    end.not_to change(Message, :count)
  end

  it 'releases the dedup lock when the payload is protocol-only' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_revoke_pascal_case.json').read)
    lock = instance_double(Whatsapp::MessageDedupLock, acquire!: true, release!: true)
    allow(Whatsapp::MessageDedupLock).to receive(:new).and_return(lock)

    described_class.new(channel: channel, data: payload['data']).perform

    expect(lock).to have_received(:release!)
  end
end
