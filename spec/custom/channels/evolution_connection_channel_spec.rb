# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EvolutionConnectionChannel, type: :channel do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'instance_name' => 'test-instance',
        'api_key' => 'TEST-KEY'
      )
    )
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }

  before do
    create(:inbox_member, inbox: inbox, user: user)
    allow(Current).to receive(:account).and_return(account)
  end

  it 'subscribes to evolution connection stream for evolution inbox' do
    subscribe(
      pubsub_token: user.pubsub_token,
      user_id: user.id,
      account_id: account.id,
      inbox_id: inbox.id
    )

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("evolution:connection:#{inbox.id}")
  end

  it 'rejects non-evolution inboxes' do
    other_channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    other_inbox = create(:inbox, account: account, channel: other_channel)

    subscribe(
      pubsub_token: user.pubsub_token,
      user_id: user.id,
      account_id: account.id,
      inbox_id: other_inbox.id
    )

    expect(subscription).to be_rejected
  end
end
