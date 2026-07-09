# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::PresenceSyncService do
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
        'api_key' => 'TEST-INSTANCE-API-KEY'
      )
    )
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }

  before do
    allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:for_channel).and_return(api_client)
  end

  it 'sends composing presence for 1:1 conversations' do
    contact = create(:contact, account: account, phone_number: '+5511999999999')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511999999999')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

    expect(api_client).to receive(:send_presence).with(
      number: '5511999999999',
      presence: 'composing',
      delay: described_class::COMPOSING_DELAY_MS
    )

    described_class.new(conversation: conversation, typing_on: true).perform
  end

  it 'sends paused presence using group source_id when phone is blank' do
    contact = create(:contact, account: account, phone_number: nil, identifier: '120363012345678901@g.us')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '120363012345678901@g.us')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

    expect(api_client).to receive(:send_presence).with(
      number: '120363012345678901@g.us',
      presence: 'paused',
      delay: described_class::PAUSED_DELAY_MS
    )

    described_class.new(conversation: conversation, typing_on: false).perform
  end
end
