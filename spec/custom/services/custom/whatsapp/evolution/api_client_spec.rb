# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::ApiClient do
  subject(:client) do
    described_class.new(
      base_url: 'https://evo.example.com',
      api_key: 'test-api-key',
      instance_name: 'test-instance'
    )
  end

  describe '#find_group_infos' do
    it 'GETs findGroupInfos with escaped groupJid query param' do
      group_jid = '120363123456789012@g.us'
      response = instance_double(HTTParty::Response, success?: true, parsed_response: { 'subject' => 'Support Team' })

      expect(HTTParty).to receive(:get).with(
        "https://evo.example.com/group/findGroupInfos/test-instance?groupJid=#{CGI.escape(group_jid)}",
        hash_including(headers: hash_including('apikey' => 'test-api-key'))
      ).and_return(response)

      result = client.find_group_infos(group_jid: group_jid)

      expect(result).to eq(response)
    end
  end

  describe '.raise_unless_success!' do
    it 'raises ApiError when response is not successful' do
      response = instance_double(HTTParty::Response, success?: false, code: 404, parsed_response: { 'message' => 'not found' })

      expect do
        described_class.raise_unless_success!(response, 'group lookup failed')
      end.to raise_error(Custom::Whatsapp::Evolution::ApiError, /group lookup failed/)
    end
  end

  describe 'retry behaviour' do
    before { allow(client).to receive(:sleep) }

    it 'retries once after a network error and returns the successful response' do
      success = instance_double(HTTParty::Response, success?: true, parsed_response: { 'subject' => 'ok' })
      call_count = 0
      allow(HTTParty).to receive(:get) do
        call_count += 1
        raise Net::ReadTimeout if call_count == 1

        success
      end

      result = client.find_group_infos(group_jid: '120363123456789012@g.us')

      expect(result).to eq(success)
      expect(HTTParty).to have_received(:get).twice
    end

    it 'raises ApiError after exhausting retries on a persistent network error' do
      allow(HTTParty).to receive(:get).and_raise(Net::ReadTimeout)

      expect do
        client.find_group_infos(group_jid: '120363123456789012@g.us')
      end.to raise_error(Custom::Whatsapp::Evolution::ApiError)
      expect(HTTParty).to have_received(:get).twice
    end

    it 'retries once on a 5xx response and returns the successful response' do
      failure = instance_double(HTTParty::Response, success?: false, code: 502, parsed_response: { 'message' => 'bad gateway' })
      success = instance_double(HTTParty::Response, success?: true, parsed_response: { 'subject' => 'ok' })
      allow(HTTParty).to receive(:get).and_return(failure, success)

      result = client.find_group_infos(group_jid: '120363123456789012@g.us')

      expect(result).to eq(success)
      expect(HTTParty).to have_received(:get).twice
    end

    it 'does not retry a 4xx response' do
      failure = instance_double(HTTParty::Response, success?: false, code: 404, parsed_response: { 'message' => 'not found' })
      allow(HTTParty).to receive(:get).and_return(failure)

      result = client.find_group_infos(group_jid: '120363123456789012@g.us')

      expect(result).to eq(failure)
      expect(HTTParty).to have_received(:get).once
    end
  end

  describe 'non-JSON responses' do
    it 'raises a catchable ApiError instead of returning an unparsed string' do
      html_response = instance_double(
        HTTParty::Response, success?: true, code: 200, parsed_response: '<html>Not JSON</html>'
      )
      allow(HTTParty).to receive(:get).and_return(html_response)

      expect do
        client.find_group_infos(group_jid: '120363123456789012@g.us')
      end.to raise_error(Custom::Whatsapp::Evolution::ApiError, /non-JSON response/)
    end

    it 'does not raise for an empty body (e.g. 204 responses)' do
      empty_response = instance_double(HTTParty::Response, success?: true, code: 204, parsed_response: '')
      allow(HTTParty).to receive(:delete).and_return(empty_response)

      expect(client.delete_instance).to eq(empty_response)
    end
  end
end
