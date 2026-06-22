class AttachmentRetentionFailure < ApplicationRecord
  belongs_to :account

  validates :attachment_id, presence: true, uniqueness: true
  validates :failure_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
