# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversations::MessageWindowService do
  describe 'on Wavoip channels' do
    let(:account) { create(:account) }
    let(:channel) { create(:channel_wavoip, account: account) }
    let(:inbox) { channel.inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    before do
      account.enable_features!('channel_voice', 'channel_wavoip')
    end

    it 'returns can_reply? false for voice-only inbox' do
      service = described_class.new(conversation)

      expect(service.can_reply?).to be false
    end
  end

  describe 'on unlimited-session WhatsApp gateway channels' do
    let(:account) { create(:account) }

    %w[evolution evolution_go].each do |provider|
      context "when provider is #{provider}" do
        let(:channel) do
          create(
            :channel_whatsapp,
            account: account,
            provider: provider,
            sync_templates: false,
            validate_provider_config: false
          )
        end
        let(:inbox) { channel.inbox }
        let(:conversation) { create(:conversation, account: account, inbox: inbox, created_at: 2.days.ago) }

        it 'bypasses the 24h messaging window (declared via MessagingProvider::Capabilities)' do
          service = described_class.new(conversation)

          expect(service.can_reply?).to be true
        end
      end
    end

    it 'does not bypass the window for providers without the unlimited_session capability' do
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      inbox = channel.inbox
      conversation = create(:conversation, account: account, inbox: inbox, created_at: 2.days.ago)

      expect(described_class.new(conversation).can_reply?).to be false
    end
  end
end
