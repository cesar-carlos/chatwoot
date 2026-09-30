# frozen_string_literal: true

# Session-level PostgreSQL advisory lock for one history migration execution.
# The database releases the lock automatically if the worker process or
# connection dies, which makes it safe for long-running jobs without a TTL.
class Custom::Inboxes::HistoryMigration::ExecutionLock
  LOCK_NAMESPACE = 734_921_117
  MAX_LOCK_ID = 2_147_483_647

  def self.synchronize(migration_id)
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      lock_id = migration_id.to_i % MAX_LOCK_ID
      acquired = connection.select_value(
        "SELECT pg_try_advisory_lock(#{LOCK_NAMESPACE}, #{lock_id})"
      )
      return false unless ActiveModel::Type::Boolean.new.cast(acquired)

      begin
        yield
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{LOCK_NAMESPACE}, #{lock_id})")
      end
      true
    end
  end
end
