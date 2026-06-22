require 'rails_helper'

RSpec.describe Custom::Retention::PurgeRetentionAuditEventsJob, type: :job do
  include ActiveJob::TestHelper

  it 'deletes audit events older than the configured retention window' do
    account = create(:account)
    old_event = AttachmentRetentionEvent.create!(
      account: account,
      attachment_id: 99_001,
      message_id: 1,
      status: 'purged',
      run_id: 'old-run',
      created_at: 400.days.ago
    )
    recent_event = AttachmentRetentionEvent.create!(
      account: account,
      attachment_id: 99_002,
      message_id: 2,
      status: 'purged',
      run_id: 'recent-run',
      created_at: 10.days.ago
    )

    with_modified_env MESSAGE_ATTACHMENT_RETENTION_AUDIT_RETENTION_DAYS: '365' do
      described_class.perform_now
    end

    expect(AttachmentRetentionEvent.exists?(old_event.id)).to be(false)
    expect(AttachmentRetentionEvent.exists?(recent_event.id)).to be(true)
  end
end
