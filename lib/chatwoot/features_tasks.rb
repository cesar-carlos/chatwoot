# frozen_string_literal: true

# rubocop:disable Rails/Output
module Chatwoot::FeaturesTasks
  module_function

  def verify_catalog!
    feature_names = YAML.safe_load(Rails.root.join('config/features.yml').read).pluck('name')
    count = feature_names.size

    puts "Feature catalog size: #{count}/64"
    abort "ERROR: feature catalog exceeds bigint capacity (#{count} > 64)" if count > 64
    puts 'WARNING: feature catalog is above 60 entries' if count > 60

    puts 'Feature catalog OK'
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
