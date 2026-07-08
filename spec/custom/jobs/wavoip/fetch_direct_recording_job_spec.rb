# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::FetchDirectRecordingJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :wavoip,
      direction: :outgoing,
      status: 'completed',
      accepted_by_agent_id: agent.id,
      provider_call_id: 'direct_fetch_001'
    )
  end
  let(:message) do
    msg = Voice::CallMessageBuilder.new(call).perform!
    call.update!(message_id: msg.id)
    msg
  end
  let(:expected_url) { 'https://storage.wavoip.com/direct_fetch_001' }

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
    message
  end

  it 'attaches the recording from the documented direct URL' do
    service = instance_double(Wavoip::Calls::RecordingAttachmentService, perform: true)
    allow(Wavoip::Calls::RecordingAttachmentService).to receive(:new)
      .with(call: call, record_url: expected_url, store_fallback_on_error: false)
      .and_return(service)

    described_class.perform_now(call.id)

    expect(service).to have_received(:perform)
  end

  it 'retries when the recording is not yet attached, up to MAX_ATTEMPTS' do
    allow_any_instance_of(Wavoip::Calls::RecordingAttachmentService).to receive(:perform) # rubocop:disable RSpec/AnyInstance

    expect { described_class.perform_now(call.id) }
      .to have_enqueued_job(described_class).with(call.id, 2)
  end

  it 'stops retrying once MAX_ATTEMPTS is reached' do
    allow_any_instance_of(Wavoip::Calls::RecordingAttachmentService).to receive(:perform) # rubocop:disable RSpec/AnyInstance

    expect { described_class.perform_now(call.id, described_class::MAX_ATTEMPTS) }
      .not_to have_enqueued_job(described_class)
  end

  it 'skips when the call is not completed' do
    call.update!(status: 'ringing')
    expect(Wavoip::Calls::RecordingAttachmentService).not_to receive(:new)

    described_class.perform_now(call.id)
  end

  it 'skips when the recording is already attached' do
    call.recording.attach(
      io: StringIO.new('audio-bytes'),
      filename: 'call.ogg',
      content_type: 'audio/ogg'
    )
    expect(Wavoip::Calls::RecordingAttachmentService).not_to receive(:new)

    described_class.perform_now(call.id)
  end

  it 'skips when a webhook already reported the recording as disabled' do
    call.update!(meta: (call.meta || {}).merge('record_status' => 'DISABLED'))
    expect(Wavoip::Calls::RecordingAttachmentService).not_to receive(:new)

    described_class.perform_now(call.id)
  end

  context 'with a real cache store (lock behavior)' do
    around do |example|
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original_cache
    end

    it 'does not fetch twice when the lock is already held for the same call' do
      Rails.cache.write("wavoip:direct_recording_lock:#{call.id}", true, unless_exist: true)
      expect(Wavoip::Calls::RecordingAttachmentService).not_to receive(:new)

      described_class.perform_now(call.id)
    end

    it 'acquires the lock atomically via unless_exist' do
      expect(Rails.cache).to receive(:write).with(
        "wavoip:direct_recording_lock:#{call.id}", true, hash_including(unless_exist: true)
      ).and_call_original
      service = instance_double(Wavoip::Calls::RecordingAttachmentService, perform: true)
      allow(Wavoip::Calls::RecordingAttachmentService).to receive(:new).and_return(service)

      described_class.perform_now(call.id)

      expect(service).to have_received(:perform)
    end
  end
end
