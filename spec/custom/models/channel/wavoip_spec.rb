# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channel::Wavoip do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }

  describe 'validations' do
    it 'requires a unique phone_number' do
      duplicate = build(:channel_wavoip, account: account, phone_number: channel.phone_number)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:phone_number]).to be_present
    end

    it 'generates a webhook_key on create' do
      expect(channel.webhook_key).to be_present
    end
  end

  describe '#voice_enabled?' do
    it 'requires channel_voice, channel_wavoip features and device_token' do
      expect(channel.voice_enabled?).to be(false)

      account.enable_features!('channel_voice')
      expect(channel.voice_enabled?).to be(false)

      account.enable_features!('channel_wavoip')
      expect(channel.voice_enabled?).to be(true)
    end
  end

  describe '#webhook_url' do
    it 'embeds the opaque webhook_key without exposing device_token' do
      url = channel.webhook_url

      expect(url).to include(channel.webhook_key)
      expect(url).not_to include(channel.device_token)
    end
  end

  describe '#setup_pending?' do
    it 'is pending until the first webhook is verified' do
      expect(channel.setup_pending?).to be(true)

      channel.update!(provider_config: { 'webhook_verified_at' => Time.current.iso8601 })
      expect(channel.setup_pending?).to be(false)
    end
  end
end
