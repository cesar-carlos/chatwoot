# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::WebhookStaleAlertJob, type: :job do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_wavoip,
      account: account,
      provider_config: {
        'webhook_verified_at' => 2.days.ago.iso8601,
        'last_webhook_at' => last_webhook_at
      }
    )
  end
  let(:last_webhook_at) { 2.days.ago.iso8601 }

  before { channel }

  it 'warns when last_webhook_at is older than 24 hours' do
    expect(Rails.logger).to receive(:warn).with(
      "[WAVOIP] stale webhook channel_id=#{channel.id} inbox_id=#{channel.inbox.id}"
    )

    described_class.perform_now
  end

  context 'when last_webhook_at is blank' do
    let(:last_webhook_at) { nil }

    it 'warns' do
      channel.update!(provider_config: channel.provider_config.except('last_webhook_at').merge(
        'webhook_verified_at' => 2.days.ago.iso8601
      ))

      expect(Rails.logger).to receive(:warn).with(/stale webhook channel_id=#{channel.id}/)

      described_class.perform_now
    end
  end

  context 'when last_webhook_at is recent' do
    let(:last_webhook_at) { 1.hour.ago.iso8601 }

    it 'does not warn' do
      expect(Rails.logger).not_to receive(:warn).with(/stale webhook/)

      described_class.perform_now
    end
  end

  context 'when webhook is not verified' do
    it 'skips the channel' do
      channel.update!(provider_config: { 'last_webhook_at' => 2.days.ago.iso8601 })

      expect(Rails.logger).not_to receive(:warn).with(/stale webhook/)

      described_class.perform_now
    end
  end
end
