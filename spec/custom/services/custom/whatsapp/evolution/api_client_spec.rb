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
end
