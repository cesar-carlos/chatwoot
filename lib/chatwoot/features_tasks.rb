# frozen_string_literal: true

# rubocop:disable Rails/Output
module Chatwoot::FeaturesTasks
  module_function

  def verify_catalog!
    features = YAML.safe_load(Rails.root.join('config/features.yml').read)
    by_column = features.group_by { |feature| feature['column'].presence || Featurable::DEFAULT_FEATURE_FLAG_COLUMN }

    by_column.each do |column, column_features|
      count = column_features.size
      puts "Feature catalog #{column}: #{count}/63"
      abort "ERROR: #{column} exceeds bigint capacity (#{count} > 63)" if count > 63
      puts "WARNING: #{column} is above 60 entries" if count > 60
    end

    puts "Feature catalog OK (#{features.size} total across #{by_column.size} column(s))"
  end

  def verify_accounts!
    failures = []

    Account.find_each(batch_size: 100) do |account|
      account.feature_flags
      account.save!(validate: false)
    rescue StandardError => e
      failures << { account_id: account.id, error: e.message }
    end

    if failures.any?
      failures.each do |failure|
        puts "Account #{failure[:account_id]}: #{failure[:error]}"
      end
      abort "ERROR: #{failures.size} account(s) failed feature flag verification"
    end

    puts "Verified #{Account.count} account(s)"
  end

  def audit_self_hosted_enterprise!
    unless ChatwootApp.self_hosted_enterprise?
      puts 'Skipping audit: installation is not self-hosted enterprise'
      return
    end

    expected = %w[
      assignment_v2 advanced_assignment sla custom_roles csat_review_notes
      conversation_required_attributes audit_logs disable_branding saml
      captain_integration captain_integration_v2 channel_voice
    ]

    Account.find_each(batch_size: 100) do |account|
      missing = expected.reject { |feature| account.feature_enabled?(feature) }
      next if missing.empty?

      puts "Account #{account.id} (#{account.name}) missing: #{missing.join(', ')}"
    end
  end

  def reconcile_jsonb!
    abort 'Accounts::FeatureStore is not loaded' unless defined?(Accounts::FeatureStore)

    mismatches = Accounts::FeatureStore.reconcile_all!
    abort "ERROR: reconciled #{mismatches} account(s) with jsonb/bitmask drift" if mismatches.positive?

    puts 'Feature store reconciliation OK'
  end
end
# rubocop:enable Rails/Output
