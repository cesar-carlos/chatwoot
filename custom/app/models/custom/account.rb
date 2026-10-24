module Custom::Account
  extend ActiveSupport::Concern

  prepended do
    has_many :conversation_workflow_rules, dependent: :destroy_async
    has_many :wavoip_channels, class_name: 'Channel::Wavoip', dependent: :destroy_async, foreign_key: 'account_id', inverse_of: :account
    has_many :attachment_retention_events, dependent: :nullify
    has_many :attachment_retention_failures, dependent: :delete_all
  end

  def workflow_rules_migrated?
    settings['workflow_rules_migrated_at'].present?
  end

  def selected_feature_flags=(features)
    if defined?(Accounts::FeatureStore) && Accounts::FeatureStore.jsonb_column_available?
      Accounts::FeatureStore.new(self).bulk_set(features)
      sync_assignment_features
    else
      super
    end
  end

  private

  # FORK: self-hosted enterprise has no Stripe plan_name but should unlock business/enterprise sync rules
  def business_or_enterprise_plan?
    return true if ChatwootApp.self_hosted_enterprise?

    super
  end
end
