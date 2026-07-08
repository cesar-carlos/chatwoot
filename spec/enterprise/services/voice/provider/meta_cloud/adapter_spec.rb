# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Voice::Provider::MetaCloud::Adapter do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              validate_provider_config: false, sync_templates: false)
  end
  let(:adapter) { described_class.new(channel) }

  before do
    account.enable_features!('channel_voice')
    channel.provider_config = channel.provider_config.merge(
      'source' => 'embedded_signup',
      'calling_enabled' => true,
      'phone_number_id' => '123456789'
    )
    channel.save!
  end

  describe '#reject_call' do
    it 'posts to the Meta calls endpoint' do
      stub_request(:post, %r{graph\.facebook\.com/.*/123456789/calls})
        .to_return(status: 200, body: '{}')

      expect(adapter.reject_call('wacid_test')).to be(true)
    end
  end

  describe '#initiate_call' do
    it 'returns parsed response on success' do
      stub_request(:post, %r{graph\.facebook\.com/.*/123456789/calls})
        .to_return(
          status: 200,
          body: { calls: [{ id: 'wacid_new' }] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = adapter.initiate_call('55669999050312', 'v=0...offer')

      expect(result.dig('calls', 0, 'id')).to eq('wacid_new')
    end
  end
end
