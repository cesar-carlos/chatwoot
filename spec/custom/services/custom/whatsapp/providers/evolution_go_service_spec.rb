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
      expect(api_client).not_to have_received(:send_text).with(hash_including(format_jid: true))
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

    def go_success(id)
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'data' => { 'Info' => { 'ID' => id } } },
        code: 200
      )
    end

    it 'sends cards as one carousel and keeps a video URL on the card header' do
      allow(api_client).to receive(:send_carousel).and_return(go_success('CAR1'))
      outgoing = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        content_type: 'cards',
        content: 'Offers',
        content_attributes: {
          items: [
            {
              title: 'Day offer',
              description: 'Only today',
              media_url: 'https://cdn.example/offer.mp4',
              actions: [{ text: 'More', type: 'link', uri: 'https://example.org/more' }]
            }
          ]
        }
      )

      expect(service.send_message('5551926346969', outgoing)).to eq('CAR1')
      expect(api_client).to have_received(:send_carousel).with(
        hash_including(
          number: '555126346969@s.whatsapp.net',
          body: 'Offers',
          cards: [
            {
              header: { videoUrl: 'https://cdn.example/offer.mp4', title: 'Day offer' },
              body: { text: 'Only today' },
              buttons: [{ type: 'URL', displayText: 'More', id: 'https://example.org/more' }]
            }
          ]
        )
      )
    end

    it 'fails a carousel card that mixes reply and link buttons' do
      allow(api_client).to receive(:send_carousel)
      outgoing = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        content_type: 'cards',
        content: 'Offers',
        content_attributes: {
          items: [
            {
              title: 'Day offer',
              description: 'Only today',
              media_url: 'https://cdn.example/offer.png',
              actions: [
                { text: 'Buy', type: 'postback', payload: 'buy' },
                { text: 'More', type: 'link', uri: 'https://example.org/more' }
              ]
            }
          ]
        }
      )

      expect(service.send_message('5551926346969', outgoing)).to be_nil
      expect(outgoing.reload).to be_failed
      expect(outgoing.external_error).to eq('Carousel card cannot mix reply and link buttons')
      expect(api_client).not_to have_received(:send_carousel)
    end

    it 'sends each article item as its own link and keeps the first source id' do
      allow(api_client).to receive(:send_link).and_return(go_success('L1'), go_success('L2'))
      replied = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        source_id: 'IN1',
        content_attributes: { evolution_go_remote_jid: '555126346969@s.whatsapp.net' }
      )
      outgoing = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        content_type: 'article',
        content: 'Reading',
        content_attributes: {
          in_reply_to_external_id: replied.source_id,
          items: [
            { title: 'Hardware', description: 'Tools', link: 'https://example.org/hardware' },
            { title: 'Search', description: 'Find', link: 'https://example.org/search' }
          ]
        }
      )

      expect(service.send_message('5551926346969', outgoing)).to eq('L1')
      expect(outgoing.reload.content_attributes['evolution_go_secondary_source_ids']).to eq(['L2'])
      expect(api_client).to have_received(:send_link).with(
        hash_including(
          url: 'https://example.org/hardware',
          title: 'Hardware',
          text: 'Reading',
          quoted: { messageId: 'IN1', participant: '555126346969@s.whatsapp.net' }
        )
      )
      expect(api_client).to have_received(:send_link).with(
        hash_including(url: 'https://example.org/search', title: 'Search')
      )
      expect(api_client).not_to have_received(:send_link).with(hash_including(text: 'Reading', url: 'https://example.org/search'))
      expect(api_client).not_to have_received(:send_link).with(hash_including(quoted: anything, url: 'https://example.org/search'))
    end

    it 'sends an input select with a description as a list' do
      allow(api_client).to receive(:send_list).and_return(go_success('LIST1'))
      allow(api_client).to receive(:send_buttons)
      outgoing = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        content_type: 'input_select',
        content: 'Choose a plan',
        content_attributes: {
          items: [
            { title: 'Basic', value: 'basic', description: 'R$ 29' },
            { title: 'Pro', value: 'pro' }
          ]
        }
      )

      service.send_message('5551926346969', outgoing)

      expect(api_client).to have_received(:send_list).with(
        hash_including(
          title: 'Choose an item',
          description: 'Choose a plan',
          button_text: 'Choose an item',
          sections: [
            {
              title: 'Choose an item',
              rows: [
                { title: 'Basic', description: 'R$ 29', rowId: 'basic' },
                { title: 'Pro', rowId: 'pro' }
              ]
            }
          ]
        )
      )
      expect(api_client).not_to have_received(:send_buttons)
    end

    it 'sends a short localized menu title and the installation name as footer' do
      account.update!(locale: 'pt_BR')
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('INSTALLATION_NAME', 'Chatwoot').and_return('Se7e Sistemas')
      allow(api_client).to receive(:send_buttons).and_return(go_success('BTN1'))
      outgoing = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        content_type: 'input_select',
        content: '',
        content_attributes: {
          items: [
            { title: 'Sim', value: 'yes' },
            { title: 'Não', value: 'no' }
          ]
        }
      )

      service.send_message('5551926346969', outgoing)

      expect(api_client).to have_received(:send_buttons).with(
        hash_including(
          title: 'Escolha um item',
          description: 'Escolha uma opção',
          footer: 'Se7e Sistemas',
          buttons: [
            { type: 'reply', displayText: 'Sim', id: 'yes' },
            { type: 'reply', displayText: 'Não', id: 'no' }
          ]
        )
      )
    end
  end
end
