FactoryBot.define do
  factory :attachment_retention_failure do
    account
    sequence(:attachment_id) { |n| n + 1_000_000 }
    failure_count { 1 }
    last_error { 'purge failed' }
    last_failed_at { Time.current }
  end
end
