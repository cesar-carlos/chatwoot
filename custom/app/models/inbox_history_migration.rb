# frozen_string_literal: true

# FORK: persists status/stats for WhatsApp inbox history migrations (A → B)
class InboxHistoryMigration < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze
  STALE_RUNNING_AFTER = 2.hours
  DEFAULT_STATS = {
    'moved' => 0,
    'merged' => 0,
    'skipped' => 0,
    'failed' => 0,
    'total' => 0
  }.freeze

  belongs_to :account
  belongs_to :source_inbox, class_name: 'Inbox'
  belongs_to :target_inbox, class_name: 'Inbox'
  belongs_to :requested_by, class_name: 'User', optional: true

  validates :status, inclusion: { in: STATUSES }

  before_validation :ensure_default_stats

  scope :actively_running, lambda {
    where(status: 'running').where(
      'COALESCE(heartbeat_at, started_at, created_at) >= ?',
      STALE_RUNNING_AFTER.ago
    )
  }

  def mark_running!
    update!(
      status: 'running',
      started_at: Time.current,
      heartbeat_at: Time.current,
      error_message: nil,
      completed_at: nil
    )
  end

  def touch_heartbeat!
    update_columns(heartbeat_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def mark_completed!
    update!(
      status: 'completed',
      heartbeat_at: Time.current,
      completed_at: Time.current,
      error_message: nil
    )
  end

  def mark_failed!(error)
    update!(
      status: 'failed',
      heartbeat_at: Time.current,
      completed_at: Time.current,
      error_message: error.to_s.truncate(2000)
    )
  end

  def stale_running?
    return false unless status == 'running'

    heartbeat = heartbeat_at || started_at || created_at
    heartbeat < STALE_RUNNING_AFTER.ago
  end

  def increment_stat!(key, by: 1)
    key = key.to_s
    current = (stats || {}).dup
    current[key] = current.fetch(key, 0).to_i + by
    update_columns(stats: current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def ensure_default_stats
    self.stats = DEFAULT_STATS.merge(stats || {})
  end
end
