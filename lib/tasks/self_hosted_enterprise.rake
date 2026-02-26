# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
namespace :chatwoot do
  namespace :self_hosted_enterprise do
    desc 'Enable self-hosted enterprise mode and account features (idempotent)'
    task enable: :environment do
      ensure_enterprise_pricing_plan!
      accounts = target_accounts
      features_to_enable = selected_features

      accounts.find_each do |account|
        enable_features_for_account(account, features_to_enable)
      end

      puts "Enable completed for #{accounts.count} account(s)"
      Rake::Task['chatwoot:self_hosted_enterprise:verify'].invoke
    end

    desc 'Verify self-hosted enterprise activation status'
    task verify: :environment do
      premium_features = available_premium_features
      accounts = target_accounts
      expected_features = selected_features
      pricing_plan = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')&.value

      puts "INSTALLATION_PRICING_PLAN=#{pricing_plan}"
      puts "self_hosted_enterprise=#{ChatwootApp.self_hosted_enterprise?}"
      puts "target_accounts=#{accounts.pluck(:id).join(',')}"
      puts "verify_mode=#{all_premium_mode? ? 'all_premium' : 'base_enterprise'}"

      accounts.find_each do |account|
        missing_features = expected_features.reject { |feature_name| account.feature_enabled?(feature_name) }
        enabled_premium = premium_features.select { |feature_name| account.feature_enabled?(feature_name) }

        puts "\naccount=#{account.id}"
        puts "missing_expected=#{missing_features.join(',')}"
        puts "enabled_premium=#{enabled_premium.join(',')}"
      end
    end

    private

    def ensure_enterprise_pricing_plan!
      config = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN')
      return if config.value == 'enterprise'

      # FORK: Self-hosted enterprise must set installation pricing plan for global gates
      config.update!(value: 'enterprise')
      GlobalConfig.clear_cache
    end

    def target_accounts
      ids = ENV.fetch('ACCOUNT_IDS', '').split(',').map(&:strip).reject(&:blank?).map(&:to_i)
      ids.present? ? Account.where(id: ids) : Account.all
    end

    def selected_features
      base_features = all_premium_mode? ? available_premium_features : base_enterprise_features
      (base_features + required_dependency_features).uniq
    end

    def all_premium_mode?
      ENV.fetch('ALL_PREMIUM', 'false').to_s == 'true'
    end

    def available_premium_features
      YAML.safe_load(Rails.root.join('config/features.yml').read)
          .select { |feature| feature['premium'] }
          .map { |feature| feature['name'] }
          .uniq
          .sort
    end

    def base_enterprise_features
      # FORK: Core features required for internal self-hosted enterprise rollout
      %w[
        assignment_v2
        advanced_assignment
        sla
        custom_roles
        csat_review_notes
        conversation_required_attributes
        audit_logs
        disable_branding
        saml
        captain_integration
        captain_integration_v2
        channel_voice
      ]
    end

    def required_dependency_features
      # FORK: Premium features may depend on internal non-premium flags
      %w[assignment_v2]
    end

    def enable_features_for_account(account, features)
      account.enable_features(*features)
      account.save!
    end
  end
end
# rubocop:enable Metrics/BlockLength
