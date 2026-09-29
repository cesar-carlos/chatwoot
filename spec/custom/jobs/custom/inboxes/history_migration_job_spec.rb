# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Inboxes::HistoryMigrationJob, type: :job do
  let(:account) { create(:account) }
  let(:source_inbox) { create(:channel_api, account: account).inbox }
  let(:target_inbox) { create(:channel_api, account: account).inbox }
  let(:migration) do
    InboxHistoryMigration.create!(
      account: account,
      source_inbox: source_inbox,
      target_inbox: target_inbox,
      status: 'pending'
    )
  end
  let(:execution_lock) { Custom::Inboxes::HistoryMigration::ExecutionLock }

  it 'does not start a second worker when the execution lock is already held' do
    allow(execution_lock).to receive(:synchronize).with(migration.id).and_return(false)

    expect(Custom::Inboxes::HistoryMigrationService).not_to receive(:new)

    described_class.perform_now(migration.id)
  end

  it 'runs the migration while holding the execution lock' do
    service = instance_double(Custom::Inboxes::HistoryMigrationService, perform: nil)
    allow(execution_lock).to receive(:synchronize) do |_migration_id, &block|
      block.call
      true
    end
    expect(Custom::Inboxes::HistoryMigrationService).to receive(:new).with(migration: migration).and_return(service)

    described_class.perform_now(migration.id)
  end

  it 'skips terminal migrations after acquiring the execution lock' do
    migration.update!(status: 'completed')
    allow(execution_lock).to receive(:synchronize) do |_migration_id, &block|
      block.call
      true
    end

    expect(Custom::Inboxes::HistoryMigrationService).not_to receive(:new)

    described_class.perform_now(migration.id)
  end
end
