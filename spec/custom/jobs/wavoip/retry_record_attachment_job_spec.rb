# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::RetryRecordAttachmentJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:provider_call_id) { 'wavoip_retry_record_001' }
  let(:record_url) { 'https://storage.wavoip.com/retry.ogg' }

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
  end

  it 'retries when the call row is not found yet' do
    expect do
      described_class.perform_now(inbox.id, provider_call_id, record_url)
    end.to have_enqueued_job(described_class).with(inbox.id, provider_call_id, record_url, 2)
  end

  it 'persists record_url meta and invokes attachment service when call exists' do
    message = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      content_type: 'voice_call',
      message_type: :incoming
    )
    call = create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      message: message,
      provider: :wavoip,
      provider_call_id: provider_call_id,
      direction: :outgoing,
      status: 'completed'
    )
    service = instance_double(Wavoip::Calls::RecordingAttachmentService, perform: true)
    allow(Wavoip::Calls::RecordingAttachmentService).to receive(:new).and_return(service)

    described_class.perform_now(inbox.id, provider_call_id, record_url)

    expect(call.reload.meta['record_url']).to eq(record_url)
    expect(Wavoip::Calls::RecordingAttachmentService).to have_received(:new).with(
      call: call,
      record_url: record_url
    )
    expect(service).to have_received(:perform)
  end

  it 'warns when retries are exhausted without finding the call' do
    allow(Rails.logger).to receive(:warn)

    described_class.perform_now(
      inbox.id,
      provider_call_id,
      record_url,
      described_class::MAX_ATTEMPTS
    )

    expect(Rails.logger).to have_received(:warn).with(
      /RECORD retry exhausted inbox_id=#{inbox.id}/
    )
  end

  it 'retries when the call exists but has no message yet' do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :wavoip,
      provider_call_id: provider_call_id,
      direction: :outgoing,
      status: 'completed',
      message: nil
    )

    expect do
      described_class.perform_now(inbox.id, provider_call_id, record_url)
    end.to have_enqueued_job(described_class).with(inbox.id, provider_call_id, record_url, 2)
  end
end
