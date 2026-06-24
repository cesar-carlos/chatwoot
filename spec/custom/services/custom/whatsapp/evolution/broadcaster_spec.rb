# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::Broadcaster do
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

  before { create(:inbox_member, inbox: inbox, user: user) }

  describe '#broadcast_disconnected' do
    it 'broadcasts evolution.connection_closed to inbox members' do
      broadcaster = described_class.new(inbox: inbox)

      expect(ActionCable.server).to receive(:broadcast).with(
        user.pubsub_token,
        hash_including(event: 'evolution.connection_closed', data: hash_including(inbox_id: inbox.id))
      )

      broadcaster.broadcast_disconnected
    end
  end
end
