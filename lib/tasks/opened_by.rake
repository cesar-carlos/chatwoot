namespace :opened_by do
  desc 'Backfill conversation opened_by from the first message. Optional ACCOUNT_ID.'
  task backfill: :environment do
    account_id = ENV.fetch('ACCOUNT_ID', nil)
    stamped = Custom::Conversations::OpenedByBackfill.perform!(account_id: account_id)
    puts "Stamped #{stamped} conversations"
  end
end
