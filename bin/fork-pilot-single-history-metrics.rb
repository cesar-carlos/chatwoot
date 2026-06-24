#!/usr/bin/env ruby
# frozen_string_literal: true

# FORK: export single-history pilot pre/post metrics to CSV
require 'csv'
require 'fileutils'

required = %w[ACCOUNT_ID PILOT_INBOX_IDS_CSV PRE_START_AT PRE_END_AT POST_START_AT POST_END_AT]
missing = required.select { |key| ENV[key].to_s.empty? }
if missing.any?
  warn "Missing required environment variables: #{missing.join(', ')}"
  warn 'Usage: bundle exec rails runner bin/fork-pilot-single-history-metrics.rb'
  exit 1
end

account_id = ENV.fetch('ACCOUNT_ID').to_i
pilot_inbox_ids_csv = ENV.fetch('PILOT_INBOX_IDS_CSV')
pre_start_at = ENV.fetch('PRE_START_AT')
pre_end_at = ENV.fetch('PRE_END_AT')
post_start_at = ENV.fetch('POST_START_AT')
post_end_at = ENV.fetch('POST_END_AT')
output_file = ENV.fetch('OUTPUT_FILE', './pilot_single_history_metrics.csv')

sql_path = Rails.root.join('doc/feature/conversation-single-history-per-channel/scripts/pilot-pre-post-metrics.sql')
sql = File.read(sql_path)
bindings = {
  account_id: account_id,
  pilot_inbox_ids_csv: pilot_inbox_ids_csv,
  pre_start_at: pre_start_at,
  pre_end_at: pre_end_at,
  post_start_at: post_start_at,
  post_end_at: post_end_at
}

result = ActiveRecord::Base.connection.exec_query(
  ActiveRecord::Base.sanitize_sql_array([sql, bindings])
)

FileUtils.mkdir_p(File.dirname(output_file))
CSV.open(output_file, 'w') do |csv|
  csv << result.columns
  result.rows.each { |row| csv << row }
end

puts "Wrote metrics to #{output_file}"
