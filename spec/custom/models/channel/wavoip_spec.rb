# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channel::Wavoip do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }

  describe 'validations' do
    it 'requires a unique phone_number per account' do
      duplicate = build(:channel_wavoip, account: account, phone_number: channel.phone_number)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:phone_number]).to be_present
    end

    it 'allows the same phone_number on different accounts' do
      other_account = create(:account)
      duplicate = build(:channel_wavoip, account: other_account, phone_number: channel.phone_number)

      expect(duplicate).to be_valid
    end

    it 'generates a webhook_key on create' do
      expect(channel.webhook_key).to be_present
    end

    it 'rejects ring_timeout_seconds above 300' do
      channel.provider_config = channel.provider_config.merge('ring_timeout_seconds' => 301)

      expect(channel).not_to be_valid
      expect(channel.errors[:ring_timeout_seconds_value]).to be_present
    end

    it 'allows ring_timeout_seconds up to 300' do
      channel.provider_config = channel.provider_config.merge('ring_timeout_seconds' => 300)

      expect(channel).to be_valid
    end

    it 'rejects include_administrators when offline fallback is none' do
      channel.provider_config = channel.provider_config.merge(
        'incoming_call_offline_fallback' => 'none',
        'incoming_call_include_administrators' => true
      )

      expect(channel).not_to be_valid
      expect(channel.errors[:provider_config]).to be_present
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

  describe '#supports_outbound_text?' do
    it 'returns false for voice-only channel' do
      expect(channel.supports_outbound_text?).to be(false)
    end
  end

  describe '#webhook_url' do
    it 'embeds the opaque webhook_key without exposing device_token' do
      with_modified_env FRONTEND_URL: 'https://app.chatwoot.com' do
        url = channel.webhook_url

        expect(url).to include(channel.webhook_key)
        expect(url).not_to include(channel.device_token)
      end
    end

    it 'returns nil when FRONTEND_URL is not configured' do
      with_modified_env FRONTEND_URL: nil do
        expect(channel.webhook_url).to be_nil
      end
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
