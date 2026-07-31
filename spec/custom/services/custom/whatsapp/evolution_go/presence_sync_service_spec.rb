# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::PresenceSyncService do
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
        'instance_token' => 'token'
      )
    )
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:api_client) { instance_double(Custom::Whatsapp::EvolutionGo::ApiClient) }

  before do
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).and_return(api_client)
  end

  it 'sends composing presence using ChatJid from contact_inbox' do
    contact = create(:contact, account: account, phone_number: '+5511999999999')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511999999999')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

    expect(api_client).to receive(:set_presence).with(
      number: '5511999999999@s.whatsapp.net',
      state: 'composing'
    )

    described_class.new(conversation: conversation, typing_on: true).perform
  end

  it 'prefers contact @lid for presence' do
    contact = create(
      :contact,
      account: account,
      phone_number: '+5511999999999',
      identifier: '123456789012345@lid'
    )
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511999999999')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

    expect(api_client).to receive(:set_presence).with(number: '123456789012345@lid', state: 'composing')

    described_class.new(conversation: conversation, typing_on: true).perform
  end

  it 'sends paused presence using group source_id when phone is blank' do
    contact = create(:contact, account: account, phone_number: nil, identifier: '120363012345678901@g.us')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '120363012345678901@g.us')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

    expect(api_client).to receive(:set_presence).with(number: '120363012345678901@g.us', state: 'paused')

    described_class.new(conversation: conversation, typing_on: false).perform
  end
end
