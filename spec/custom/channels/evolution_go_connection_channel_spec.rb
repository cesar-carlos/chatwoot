# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EvolutionGoConnectionChannel, type: :channel do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_name' => 'go-instance'
      )
    )
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }

  def subscribe_as(user)
    stub_connection(
      current_user: user,
      current_account: account,
      params: {
        inbox_id: inbox.id,
        pubsub_token: user.pubsub_token,
        account_id: account.id,
        user_id: user.id
      }
    )
    subscribe
  end

  it 'allows administrators to subscribe' do
    subscribe_as(admin)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("evolution_go:connection:#{inbox.id}")
  end

  it 'rejects non-admin agents' do
    create(:inbox_member, inbox: inbox, user: agent)
    subscribe_as(agent)
    expect(subscription).to be_rejected
  end
end
