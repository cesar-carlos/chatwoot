# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::ApiClient do
  let(:client) do
    described_class.new(
      base_url: 'https://go.example.com',
      global_api_key: 'global-key',
      instance_token: 'instance-token',
      instance_name: 'test-instance'
    )
  end

  describe '#dig_field' do
    it 'accepts PascalCase and camelCase keys' do
      hash = { 'Connected' => true, 'loggedIn' => false, 'myJid' => '5511@s.whatsapp.net' }

      expect(client.dig_field(hash, 'connected', 'Connected')).to be(true)
      expect(client.dig_field(hash, 'loggedIn', 'LoggedIn')).to be(false)
      expect(client.dig_field(hash, 'jid', 'myJid', 'JID')).to eq('5511@s.whatsapp.net')
    end
  end

  describe 'retry and non-JSON handling' do
    it 'retries once on 502 responses' do
      stub_request(:get, 'https://go.example.com/instance/status')
        .to_return(
          { status: 502, body: 'bad gateway' },
          { status: 200, body: { message: 'success', data: { Connected: true } }.to_json }
        )

      response = client.connection_status
      expect(response.success?).to be(true)
      expect(WebMock).to have_requested(:get, 'https://go.example.com/instance/status').twice
    end

    it 'raises ApiError on non-JSON responses' do
      stub_request(:get, 'https://go.example.com/server/ok')
        .to_return(status: 200, body: 'not json', headers: { 'Content-Type' => 'application/json' })

      expect { client.server_ok }.to raise_error(Custom::Whatsapp::EvolutionGo::ApiError, /non-JSON/)
    end
  end

  describe '#group_info' do
    it 'posts groupJid to /group/info' do
      stub_request(:post, 'https://go.example.com/group/info')
        .with(body: { groupJid: '120363012345678901@g.us' })
        .to_return(status: 200, body: { data: { Name: 'Support Team' } }.to_json)

      response = client.group_info(group_jid: '120363012345678901@g.us')
      expect(response.success?).to be(true)
    end
  end

  describe '#pair' do
    it 'posts phone and subscribe to /instance/pair' do
      stub_request(:post, 'https://go.example.com/instance/pair')
        .with(
          body: {
            phone: '5511999999999',
            subscribe: %w[MESSAGE CONNECTION QRCODE]
          }
        )
        .to_return(
          status: 200,
          body: { message: 'success', data: { PairingCode: 'ABCD-1234' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      response = client.pair(phone: '5511999999999', subscribe: %w[MESSAGE CONNECTION QRCODE])
      expect(response.success?).to be(true)
      expect(
        client.dig_field(client.unwrap(response, context: 'pair'), 'pairingCode', 'PairingCode')
      ).to eq('ABCD-1234')
    end
  end

  describe '#send_location' do
    it 'posts latitude and longitude to /send/location' do
      stub_request(:post, 'https://go.example.com/send/location')
        .with(
          body: hash_including(
            number: '5511999999999',
            latitude: -23.55,
            longitude: -46.63,
            name: 'São Paulo'
          )
        )
        .to_return(status: 200, body: { data: { Info: { ID: 'LOC1' } } }.to_json)

      response = client.send_location(
        number: '5511999999999',
        latitude: -23.55,
        longitude: -46.63,
        name: 'São Paulo'
      )
      expect(response.success?).to be(true)
    end
  end

  describe '#set_presence' do
    it 'posts composing state to /message/presence' do
      stub_request(:post, 'https://go.example.com/message/presence')
        .with(body: { number: '5511999999999', state: 'composing', isAudio: false })
        .to_return(status: 200, body: { message: 'success' }.to_json)

      response = client.set_presence(number: '5511999999999', state: 'composing')
      expect(response.success?).to be(true)
    end
  end

  describe '#send_media' do
    it 'posts to /send/media with quoted context' do
      stub_request(:post, 'https://go.example.com/send/media')
        .with(
          body: hash_including(
            number: '5511999999999',
            type: 'image',
            url: 'https://example.com/photo.jpg',
            quoted: { messageId: 'ABC', participant: '5511888888888@s.whatsapp.net' }
          )
        )
        .to_return(status: 200, body: { data: { Info: { ID: 'OUT1' } } }.to_json)

      response = client.send_media(
        number: '5511999999999',
        type: 'image',
        url: 'https://example.com/photo.jpg',
        quoted: { messageId: 'ABC', participant: '5511888888888@s.whatsapp.net' }
      )
      expect(response.success?).to be(true)
    end
  end

  describe '#mark_messages_read' do
    it 'posts message ids to /message/markread' do
      stub_request(:post, 'https://go.example.com/message/markread')
        .with(body: { number: '5511999999999', id: %w[MSG1 MSG2] })
        .to_return(status: 200, body: { message: 'success' }.to_json)

      expect(client.mark_messages_read(number: '5511999999999', ids: %w[MSG1 MSG2]).success?).to be(true)
    end
  end

  describe '#download_media' do
    it 'posts to /message/downloadmedia' do
      stub_request(:post, 'https://go.example.com/message/downloadmedia')
        .to_return(status: 200, body: { base64: Base64.strict_encode64('bytes') }.to_json)

      envelope = {
        key: { id: 'MSG1', remoteJid: '5511@s.whatsapp.net' },
        message: { imageMessage: { mimetype: 'image/jpeg' } }
      }
      response = client.download_media(envelope)
      expect(response.success?).to be(true)
      expect(WebMock).to have_requested(:post, 'https://go.example.com/message/downloadmedia').once
    end
  end

  describe '#send_contact' do
    it 'posts vcard payload to /send/contact' do
      stub_request(:post, 'https://go.example.com/send/contact')
        .with(
          body: hash_including(
            'number' => '5511999999999',
            'vcard' => hash_including('fullName' => 'Maria', 'phone' => '5511888888888')
          )
        )
        .to_return(status: 200, body: { data: { Info: { ID: 'CONTACT1' } } }.to_json)

      response = client.send_contact(
        number: '5511999999999',
        vcard: { fullName: 'Maria', phone: '5511888888888' }
      )
      expect(response.success?).to be(true)
    end
  end

  describe '#react' do
    it 'posts reaction payload to /message/react and uses short timeout' do
      stub_request(:post, 'https://go.example.com/message/react')
        .with(
          body: hash_including(
            'id' => 'TARGETMSG1',
            'reaction' => '👍'
          )
        )
        .to_return(status: 200, body: { message: 'success' }.to_json)

      expect(described_class::REACT_REQUEST_TIMEOUT).to eq(15)
      expect(described_class::NON_RETRYABLE_PATHS).to include('/message/react')
      expect(described_class::NON_RETRYABLE_PATHS).to include('/user/info')

      response = client.react(number: '5511999999999', id: 'TARGETMSG1', reaction: '👍')
      expect(response.success?).to be(true)
      expect(WebMock).to have_requested(:post, 'https://go.example.com/message/react').once
    end
  end
end
