# frozen_string_literal: true

class Custom::Inboxes::HistoryMigrationJob < ApplicationJob
  queue_as :low

  def perform(migration_id)
    migration = InboxHistoryMigration.find_by(id: migration_id)
    return if migration.blank?
    return if migration.status.in?(%w[completed failed])

    Custom::Inboxes::HistoryMigration::CompatibilityGuard.expire_stale_for_inbox_ids!(
      [migration.source_inbox_id, migration.target_inbox_id]
    )
    return if migration.reload.status == 'failed'

    if competing_migration?(migration)
      migration.mark_failed!('Another history migration is already in progress for these inboxes')
      return
    end

    Custom::Inboxes::HistoryMigrationService.new(migration: migration).perform
  end

  private

  def competing_migration?(migration)
    InboxHistoryMigration
      .blocking_progress
      .for_inbox_ids([migration.source_inbox_id, migration.target_inbox_id])
      .where.not(id: migration.id)
      .exists?(['id < ?', migration.id])
  end
end
