# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::MarkReadService do
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
        'mark_read_on_open' => true
      )
    )
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:api_client) { instance_double(Custom::Whatsapp::EvolutionGo::ApiClient) }
  let(:mark_read_response) { instance_double(HTTParty::Response, success?: true, code: 200) }

  before do
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).and_return(api_client)
  end

  it 'marks unread incoming messages using ChatJid from contact_inbox' do
    contact = create(:contact, account: account, phone_number: '+5511999999999')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511999999999')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming,
                     source_id: 'MSG1', status: :sent)

    expect(api_client).to receive(:mark_messages_read).with(
      number: '5511999999999@s.whatsapp.net',
      ids: ['MSG1']
    ).and_return(mark_read_response)

    perform_enqueued_jobs { described_class.new(conversation: conversation).perform }
  end

  it 'prefers stored WITHOUT-9 remote_jid over WITH-9 phone' do
    contact = create(
      :contact,
      account: account,
      phone_number: '+5551926346969',
      additional_attributes: {
        Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY =>
          '555126346969@s.whatsapp.net'
      }
    )
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5551926346969')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming,
                     source_id: 'MSG1', status: :sent)

    expect(api_client).to receive(:mark_messages_read).with(
      number: '555126346969@s.whatsapp.net',
      ids: ['MSG1']
    ).and_return(mark_read_response)

    perform_enqueued_jobs { described_class.new(conversation: conversation).perform }
  end

  it 'falls back to group contact_inbox source_id when phone_number is blank' do
    contact = create(:contact, account: account, phone_number: nil, identifier: '120363012345678901@g.us')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '120363012345678901@g.us')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming,
                     source_id: 'GROUPMSG1', status: :sent)

    expect(api_client).to receive(:mark_messages_read).with(
      number: '120363012345678901@g.us',
      ids: ['GROUPMSG1']
    ).and_return(mark_read_response)

    perform_enqueued_jobs { described_class.new(conversation: conversation).perform }
  end

  it 'marks read when mark_read_on_open is missing' do
    channel.update!(provider_config: channel.provider_config.except('mark_read_on_open'))
    contact = create(:contact, account: account, phone_number: '+5511999999999')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511999999999')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming,
                     source_id: 'MSG1', status: :sent)

    expect(api_client).to receive(:mark_messages_read).and_return(mark_read_response)

    perform_enqueued_jobs { described_class.new(conversation: conversation).perform }
  end

  it 'sends unread ids in batches of 20 and stops when Evolution Go rejects a batch' do
    contact = create(:contact, account: account, phone_number: '+5511999999999')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511999999999')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    service = described_class.new(conversation: conversation)
    ids = (1..25).map { |index| "MSG#{index}" }
    allow(service).to receive(:unread_incoming_source_ids).and_return(ids)

    expect(api_client).to receive(:mark_messages_read).with(
      number: '5511999999999@s.whatsapp.net',
      ids: ids.first(20)
    ).and_return(instance_double(HTTParty::Response, success?: false, code: 422)).once
    expect(Rails.logger).to receive(:warn).with(/mark read failed/)

    perform_enqueued_jobs { service.perform }
  end

  it 'enqueues at most 100 unread ids' do
    contact = create(:contact, account: account, phone_number: '+5511999999999')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511999999999')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    service = described_class.new(conversation: conversation)
    ids = (1..120).map { |index| "M#{index}" }
    allow(service).to receive(:unread_incoming_source_ids).and_return(ids)

    expect(Custom::Whatsapp::EvolutionGo::MarkReadJob).to receive(:perform_later).with(
      channel.id,
      '5511999999999@s.whatsapp.net',
      ids.first(100)
    )

    service.perform
  end
end
