# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Providers::EvolutionGoService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'base_url' => 'https://go.example.com',
        'instance_token' => 'instance-token',
        'instance_name' => 'test-instance'
      )
    )
  end
  let(:service) { described_class.new(whatsapp_channel: channel) }
  let(:message) { create(:message, account: account, inbox: create(:inbox, account: account, channel: channel)) }

  describe '#process_response' do
    it 'extracts source_id from data.Info.ID' do
      fixture = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/send_text_response.json').read)
      response = instance_double(HTTParty::Response, success?: true, parsed_response: fixture)

      expect(service.send(:process_response, response, message)).to eq('3EB0OUTBOUND123')
    end
  end

  describe '#send_message' do
    let(:api_client) { instance_double(Custom::Whatsapp::EvolutionGo::ApiClient) }
    let(:inbox) { channel.inbox }
    let(:contact) do
      create(
        :contact,
        account: account,
        phone_number: '+5551926346969',
        additional_attributes: {
          Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY =>
            '555126346969@s.whatsapp.net'
        }
      )
    end
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5551926346969') }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

    before do
      allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).and_return(api_client)
      allow(api_client).to receive(:send_text).and_return(
        instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Info' => { 'ID' => 'TXT1' } } })
      )
      allow(api_client).to receive(:send_location).and_return(
        instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Info' => { 'ID' => 'LOC1' } } })
      )
    end

    it 'sends to contact stored WITHOUT-9 remote_jid instead of WITH-9 source_id' do
      outgoing = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        content: 'hello'
      )

      service.send_message('5551926346969', outgoing)

      expect(api_client).to have_received(:send_text).with(
        hash_including(number: '555126346969@s.whatsapp.net')
      )
    end

    it 'sets formatJid when destination is @lid' do
      contact.update!(identifier: '123456789012345@lid')
      outgoing = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        content: 'hello'
      )

      service.send_message('5551926346969', outgoing)

      expect(api_client).to have_received(:send_text).with(
        hash_including(number: '123456789012345@lid', format_jid: true)
      )
    end

    it 'includes quoted context when replying' do
      replied = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        source_id: 'INCOMING1',
        content_attributes: { evolution_go_remote_jid: '555126346969@s.whatsapp.net' }
      )
      reply_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        content_attributes: { in_reply_to_external_id: replied.source_id }
      )

      service.send_message('5551926346969', reply_message)

      expect(api_client).to have_received(:send_text).with(
        hash_including(
          quoted: {
            messageId: 'INCOMING1',
            participant: '555126346969@s.whatsapp.net'
          }
        )
      )
    end

    it 'quotes own outgoing messages using business JID from instance_name when channel phone is placeholder' do
      channel.update!(phone_number: '+55000abcdef')
      channel.update!(
        provider_config: channel.provider_config.merge(
          'instance_name' => 'FORTEZA-FATURAMENTO-66996950396-1070BEFB08'
        )
      )

      own = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        source_id: 'OUTGOING1',
        content_attributes: { evolution_go_remote_jid: '555126346969@s.whatsapp.net' }
      )
      reply_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        content_attributes: { in_reply_to_external_id: own.source_id }
      )

      service.send_message('5551926346969', reply_message)

      expect(api_client).to have_received(:send_text).with(
        hash_including(
          quoted: {
            messageId: 'OUTGOING1',
            participant: '5566996950396@s.whatsapp.net'
          }
        )
      )
    end

    it 'sends location attachments via send_location to ChatJid destination' do
      location_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation
      )
      location_message.attachments.create!(
        account: account,
        file_type: :location,
        coordinates_lat: -23.55,
        coordinates_long: -46.63,
        fallback_title: 'São Paulo'
      )

      service.send_message('5551926346969', location_message)

      expect(api_client).to have_received(:send_location).with(
        hash_including(
          number: '555126346969@s.whatsapp.net',
          latitude: -23.55,
          longitude: -46.63,
          name: 'São Paulo'
        )
      )
    end

    it 'quotes group inbound messages using participant jid not @g.us' do
      group_jid = '120363012345678901@g.us'
      contact.update!(phone_number: nil, identifier: group_jid)
      contact_inbox.update!(source_id: group_jid)
      replied = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        source_id: 'GROUPIN1',
        content_attributes: {
          evolution_go_remote_jid: group_jid,
          evolution_go_participant_jid: '5511777777777@s.whatsapp.net'
        }
      )
      reply_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        content_attributes: { in_reply_to_external_id: replied.source_id }
      )

      service.send_message(group_jid, reply_message)

      expect(api_client).to have_received(:send_text).with(
        hash_including(
          number: group_jid,
          quoted: {
            messageId: 'GROUPIN1',
            participant: '5511777777777@s.whatsapp.net'
          }
        )
      )
    end
  end
end
