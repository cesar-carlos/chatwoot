# frozen_string_literal: true

namespace :chatwoot do
  namespace :features do
    desc 'Verify feature catalog size and warn when approaching bigint capacity'
    task verify_catalog: :environment do
      Chatwoot::FeaturesTasks.verify_catalog!
    end

    desc 'Verify account feature bitmasks are persistible'
    task verify_accounts: :environment do
      Chatwoot::FeaturesTasks.verify_accounts!
    end

    desc 'Audit enabled premium features against self-hosted enterprise expectations'
    task audit: :environment do
      Chatwoot::FeaturesTasks.audit_self_hosted_enterprise!
    end

    desc 'Reconcile jsonb feature store with legacy bitmasks'
    task reconcile_jsonb: :environment do
      Chatwoot::FeaturesTasks.reconcile_jsonb!
    end
  end
end
