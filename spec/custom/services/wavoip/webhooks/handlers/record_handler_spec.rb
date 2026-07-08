# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Webhooks::Handlers::RecordHandler do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:provider_call_id) { 'wavoip_record_001' }
  let(:record_url) { 'https://storage.wavoip.com/wavoip_record_001.ogg' }
  let!(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :wavoip,
      provider_call_id: provider_call_id,
      direction: :outgoing,
      status: 'completed'
    )
  end
  let(:event) do
    Voice::Dto::WebhookCallEvent.new(
      provider: :wavoip,
      external_call_id: provider_call_id,
      action: :update,
      external_status: nil,
      direction: nil,
      from_phone: channel.phone_number,
      to_phone: nil,
      peer_name: nil,
      duration_seconds: nil,
      session_id: nil,
      call_type: nil,
      record_url: record_url,
      record_status: 'READY',
      raw_type: 'RECORD'
    )
  end

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
  end

  it 'updates call meta and enqueues AttachRecordingJob' do
    expect do
      described_class.new(inbox: inbox, event: event).perform
    end.to have_enqueued_job(Wavoip::AttachRecordingJob).with(call.id, record_url)

    expect(call.reload.meta['record_url']).to eq(record_url)
    expect(call.meta['record_status']).to eq('READY')
  end

  it 'is idempotent when the same record_url is already stored' do
    call.update!(meta: { 'record_url' => record_url })

    expect do
      described_class.new(inbox: inbox, event: event).perform
    end.not_to have_enqueued_job(Wavoip::AttachRecordingJob)
  end

  it 'skips when record_url is blank' do
    blank_event = Voice::Dto::WebhookCallEvent.new(
      provider: :wavoip,
      external_call_id: provider_call_id,
      action: :update,
      external_status: nil,
      direction: nil,
      from_phone: channel.phone_number,
      to_phone: nil,
      peer_name: nil,
      duration_seconds: nil,
      session_id: nil,
      call_type: nil,
      record_url: nil,
      record_status: nil,
      raw_type: 'RECORD'
    )

    expect do
      described_class.new(inbox: inbox, event: blank_event).perform
    end.not_to have_enqueued_job(Wavoip::AttachRecordingJob)
  end

  it 'skips when the call cannot be found and enqueues retry job' do
    missing_event = Voice::Dto::WebhookCallEvent.new(
      provider: :wavoip,
      external_call_id: 'missing_call',
      action: :update,
      external_status: nil,
      direction: nil,
      from_phone: channel.phone_number,
      to_phone: nil,
      peer_name: nil,
      duration_seconds: nil,
      session_id: nil,
      call_type: nil,
      record_url: record_url,
      record_status: 'READY',
      raw_type: 'RECORD'
    )

    expect do
      described_class.new(inbox: inbox, event: missing_event).perform
    end.to have_enqueued_job(Wavoip::RetryRecordAttachmentJob)
      .with(inbox.id, 'missing_call', record_url, record_status: 'READY')
  end

  it 'skips attach when call_recording_enabled is false' do
    channel.update!(provider_config: channel.provider_config.merge('call_recording_enabled' => false))

    expect do
      described_class.new(inbox: inbox, event: event).perform
    end.not_to have_enqueued_job(Wavoip::AttachRecordingJob)

    expect(call.reload.meta['record_url']).to be_nil
  end

  it 'persists record_status without attach while recording is processing' do
    processing_event = Voice::Dto::WebhookCallEvent.new(
      provider: :wavoip,
      external_call_id: provider_call_id,
      action: :update,
      external_status: nil,
      direction: nil,
      from_phone: channel.phone_number,
      to_phone: nil,
      peer_name: nil,
      duration_seconds: nil,
      session_id: nil,
      call_type: nil,
      record_url: record_url,
      record_status: 'RECORDING',
      raw_type: 'RECORD'
    )

    expect do
      described_class.new(inbox: inbox, event: processing_event).perform
    end.not_to have_enqueued_job(Wavoip::AttachRecordingJob)

    expect(call.reload.meta['record_status']).to eq('RECORDING')
    expect(call.meta['record_url']).to be_nil
  end

  it 'does not enqueue attach while call is still in progress' do
    call.update!(status: 'in_progress')
    in_progress_event = Voice::Dto::WebhookCallEvent.new(
      provider: :wavoip,
      external_call_id: provider_call_id,
      action: :update,
      external_status: nil,
      direction: nil,
      from_phone: channel.phone_number,
      to_phone: nil,
      peer_name: nil,
      duration_seconds: nil,
      session_id: nil,
      call_type: nil,
      record_url: record_url,
      record_status: 'READY',
      raw_type: 'RECORD'
    )

    expect do
      described_class.new(inbox: inbox, event: in_progress_event).perform
    end.not_to have_enqueued_job(Wavoip::AttachRecordingJob)
  end
end
