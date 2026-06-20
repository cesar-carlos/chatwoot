# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::AttachRecordingJob, type: :job do
  let(:account) { create(:account) }
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
      provider_call_id: 'attach_job_001',
      direction: :outgoing,
      status: 'completed'
    )
  end
  let(:record_url) { 'https://example.com/recording.ogg' }
  let(:service) { instance_double(Wavoip::Calls::RecordingAttachmentService, perform: true) }

  before do
    allow(Wavoip::Calls::RecordingAttachmentService).to receive(:new)
      .with(call: call, record_url: record_url)
      .and_return(service)
  end

  it 'delegates to RecordingAttachmentService' do
    described_class.perform_now(call.id, record_url)

    expect(Wavoip::Calls::RecordingAttachmentService).to have_received(:new)
      .with(call: call, record_url: record_url)
    expect(service).to have_received(:perform)
  end

  it 'no-ops when the call is missing' do
    expect(Wavoip::Calls::RecordingAttachmentService).not_to receive(:new)

    described_class.perform_now(-1, record_url)
  end

  it 'no-ops when record_url is blank' do
    expect(Wavoip::Calls::RecordingAttachmentService).not_to receive(:new)

    described_class.perform_now(call.id, nil)
  end
end
