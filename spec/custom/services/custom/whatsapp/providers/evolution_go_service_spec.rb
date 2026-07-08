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

    before do
      allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).and_return(api_client)
      allow(api_client).to receive(:send_text).and_return(
        instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Info' => { 'ID' => 'TXT1' } } })
      )
      allow(api_client).to receive(:send_location).and_return(
        instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Info' => { 'ID' => 'LOC1' } } })
      )
    end

    it 'includes quoted context when replying' do
      replied = create(
        :message,
        account: account,
        inbox: message.inbox,
        conversation: message.conversation,
        message_type: :incoming,
        source_id: 'INCOMING1',
        content_attributes: { evolution_go_remote_jid: '5511999999999@s.whatsapp.net' }
      )
      reply_message = create(
        :message,
        account: account,
        inbox: message.inbox,
        conversation: message.conversation,
        content_attributes: { in_reply_to_external_id: replied.source_id }
      )

      service.send_message('5511999999999', reply_message)

      expect(api_client).to have_received(:send_text).with(
        hash_including(
          quoted: {
            messageId: 'INCOMING1',
            participant: '5511999999999@s.whatsapp.net'
          }
        )
      )
    end

    it 'sends location attachments via send_location' do
      location_message = create(
        :message,
        account: account,
        inbox: message.inbox,
        conversation: message.conversation
      )
      location_message.attachments.create!(
        account: account,
        file_type: :location,
        coordinates_lat: -23.55,
        coordinates_long: -46.63,
        fallback_title: 'São Paulo'
      )

      service.send_message('5511999999999', location_message)

      expect(api_client).to have_received(:send_location).with(
        hash_including(
          number: '5511999999999',
          latitude: -23.55,
          longitude: -46.63,
          name: 'São Paulo'
        )
      )
    end
  end
end
