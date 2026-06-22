class AttachmentRetentionEvent < ApplicationRecord
  STATUSES = %w[purged dry_run failed skipped_quarantine].freeze

  belongs_to :account, optional: true

  validates :attachment_id, :status, :run_id, presence: true
  validates :status, inclusion: { in: STATUSES }
end
