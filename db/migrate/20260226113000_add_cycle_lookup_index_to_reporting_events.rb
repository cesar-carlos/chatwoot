class AddCycleLookupIndexToReportingEvents < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :reporting_events,
              [:conversation_id, :name, :event_end_time],
              name: 'index_reporting_events_on_cycle_lookup',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
