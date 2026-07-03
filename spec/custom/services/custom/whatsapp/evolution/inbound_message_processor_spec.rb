# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::InboundMessageProcessor do
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
  let(:inbox) { channel.inbox }
  let(:params) do
    {
      contacts: [{ profile: { name: 'Alice' }, wa_id: '5511999999999' }],
      messages: [{ from: '5511999999999', id: 'MSG-1', type: 'text', text: { body: 'hi' } }]
    }
  end
  let(:service) { instance_double(Whatsapp::IncomingMessageService, perform: nil) }

  before do
    allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(service)
  end

  it 'delegates normalized params to IncomingMessageService' do
    described_class.process(channel, params)

    expect(Whatsapp::IncomingMessageService).to have_received(:new).with(
      inbox: inbox,
      params: params
    )
    expect(service).to have_received(:perform)
  end
end
