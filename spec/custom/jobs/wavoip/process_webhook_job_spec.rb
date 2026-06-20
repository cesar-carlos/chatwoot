# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::ProcessWebhookJob, type: :job do
  let(:payload) { { 'type' => 'DEVICE', 'status' => 'open' } }

  it 'logs and drops webhooks when the inbox no longer exists' do
    expect(Rails.logger).to receive(:warn).with(/Dropping webhook: inbox_id=99999 not found/)

    expect do
      described_class.perform_now(99_999, payload)
    end.not_to have_enqueued_job(described_class)
  end
end
