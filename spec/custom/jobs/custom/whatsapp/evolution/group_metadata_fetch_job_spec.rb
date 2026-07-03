# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::GroupMetadataFetchJob, type: :job do
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
        'api_key' => 'TEST-KEY'
      )
    )
  end
  let(:group_jid) { '120363123456789012@g.us' }
  let(:metadata_service) { instance_double(Custom::Whatsapp::Evolution::GroupMetadataService, warm_cache!: 'Team (GROUP)') }

  before do
    allow(Custom::Whatsapp::Evolution::GroupMetadataService).to receive(:new).and_return(metadata_service)
  end

  it 'warms group metadata cache for the channel' do
    described_class.perform_now(channel.id, group_jid)

    expect(Custom::Whatsapp::Evolution::GroupMetadataService).to have_received(:new).with(channel: channel)
    expect(metadata_service).to have_received(:warm_cache!).with(group_jid)
  end

  it 'no-ops when the channel is missing' do
    expect(Custom::Whatsapp::Evolution::GroupMetadataService).not_to receive(:new)

    described_class.perform_now(-1, group_jid)
  end
end
