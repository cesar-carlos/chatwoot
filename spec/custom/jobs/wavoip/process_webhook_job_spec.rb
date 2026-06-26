# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::ProcessWebhookJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:payload) { { 'type' => 'DEVICE', 'status' => 'open', 'action' => 'UPDATE' } }

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
  end

  describe 'queue selection' do
    it 'enqueues CALL webhooks on the default queue' do
      expect do
        described_class.perform_later(inbox.id, { 'type' => 'CALL', 'action' => 'INCOMING_RING' })
      end.to have_enqueued_job(described_class).on_queue('default')
    end

    it 'enqueues DEVICE webhooks on the default queue' do
      expect do
        described_class.perform_later(inbox.id, payload)
      end.to have_enqueued_job(described_class).on_queue('default')
    end

    it 'enqueues RECORD webhooks on the low queue' do
      expect do
        described_class.perform_later(inbox.id, { 'type' => 'RECORD', 'record_url' => 'https://example.com/rec.mp3' })
      end.to have_enqueued_job(described_class).on_queue('low')
    end
  end

  it 'logs and drops webhooks when the inbox no longer exists' do
    expect(Rails.logger).to receive(:warn).with(/Dropping webhook: inbox_id=99999 not found/)

    expect do
      described_class.perform_now(99_999, payload)
    end.not_to have_enqueued_job(described_class)
  end

  it 'logs structured fields without dumping ActiveRecord objects' do
    wavoip_log = nil
    allow(Rails.logger).to receive(:info) do |message|
      wavoip_log = message if message.is_a?(String) && message.start_with?('[WAVOIP] processed')
    end

    described_class.perform_now(inbox.id, payload)

    expect(wavoip_log).to include(
      "inbox_id=#{inbox.id}",
      'type=DEVICE',
      'action=UPDATE',
      'status=open',
      'outcome=processed'
    )
    expect(wavoip_log).not_to match(/#<(?:Call|Inbox|Channel)/)
  end
end
