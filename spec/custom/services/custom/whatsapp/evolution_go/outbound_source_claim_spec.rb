# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::OutboundSourceClaim do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_token' => 'token',
        'instance_name' => 'test-go-instance'
      )
    )
  end
  let(:message) { create(:message, account: account, inbox: channel.inbox, message_type: :outgoing) }

  it 'stores the source id when the dedup lock is acquired' do
    lock = instance_double(Whatsapp::MessageDedupLock, acquire!: true, release!: true)
    allow(Custom::Whatsapp::EvolutionGo::MessageDedupLock).to receive(:build).and_return(lock)

    described_class.claim!(message, '3EB0OUTBOUND123')

    expect(message.reload.source_id).to eq('3EB0OUTBOUND123')
    expect(lock).to have_received(:release!)
  end

  it 'leaves the agent message unchanged when the echo already holds the lock' do
    lock = instance_double(Whatsapp::MessageDedupLock, acquire!: false, release!: true)
    allow(Custom::Whatsapp::EvolutionGo::MessageDedupLock).to receive(:build).and_return(lock)

    described_class.claim!(message, '3EB0OUTBOUND123')

    expect(message.reload.source_id).to be_blank
    expect(lock).not_to have_received(:release!)
  end
end
