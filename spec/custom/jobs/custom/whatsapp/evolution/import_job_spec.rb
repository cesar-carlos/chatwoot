# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::ImportJob do
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
        'api_key' => 'TEST-KEY',
        'import_contacts' => true
      )
    )
  end
  let(:import_service) { instance_double(Custom::Whatsapp::Evolution::ImportService, perform: nil) }

  before do
    create(:inbox, account: account, channel: channel)
    allow(Custom::Whatsapp::Evolution::ImportService).to receive(:new).and_return(import_service)
  end

  it 'delegates to ImportService' do
    described_class.perform_now(channel.id, force: true)

    expect(Custom::Whatsapp::Evolution::ImportService).to have_received(:new).with(channel: channel, force: true)
    expect(import_service).to have_received(:perform)
  end

  it 'no-ops for missing channel' do
    described_class.perform_now(-1)

    expect(import_service).not_to have_received(:perform)
  end
end
