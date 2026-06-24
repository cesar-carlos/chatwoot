# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::OutgoingMessageHelper do
  let(:helper_class) do
    Class.new do
      include Custom::Whatsapp::Evolution::OutgoingMessageHelper

      attr_accessor :channel

      def initialize(channel)
        @channel = channel
      end
    end
  end
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
  let(:helper) { helper_class.new(channel) }

  describe '#outgoing_content' do
    it 'prefers normalized text body over raw record' do
      record = { 'message' => { 'conversation' => 'raw' } }
      message_data = { type: 'text', text: { body: 'normalized' } }

      expect(helper.outgoing_content(record, message_data)).to eq('normalized')
    end

    it 'uses media caption when present' do
      record = { 'message' => {} }
      message_data = { type: 'image', image: { caption: 'photo caption' } }

      expect(helper.outgoing_content(record, message_data)).to eq('photo caption')
    end
  end

  describe '#outgoing_media_message?' do
    it 'detects supported media types' do
      expect(helper.outgoing_media_message?({ type: 'image', image: { id: '1' } })).to be(true)
      expect(helper.outgoing_media_message?({ type: 'text', text: { body: 'hi' } })).to be(false)
    end
  end
end
