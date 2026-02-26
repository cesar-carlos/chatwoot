class AddPeriodIndexesToReportingEventsForServiceSessions < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :reporting_events,
              [:account_id, :name, :event_end_time],
              name: 'index_reporting_events_on_account_name_event_end_time',
              algorithm: :concurrently,
              if_not_exists: true

    add_index :reporting_events,
              [:account_id, :inbox_id, :name, :event_end_time],
              name: 'index_reporting_events_on_account_inbox_name_event_end_time',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
