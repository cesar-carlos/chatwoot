# frozen_string_literal: true

class Custom::Inboxes::HistoryMigrationJob < ApplicationJob
  queue_as :low

  def perform(migration_id)
    migration = InboxHistoryMigration.find_by(id: migration_id)
    return if migration.blank?
    return if migration.status.in?(%w[completed failed])

    Custom::Inboxes::HistoryMigrationService.new(migration: migration).perform
  end
end
