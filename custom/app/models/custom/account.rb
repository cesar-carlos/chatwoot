module Custom::Account
  extend ActiveSupport::Concern

  prepended do
    has_many :conversation_workflow_rules, dependent: :destroy_async
  end

  def workflow_rules_migrated?
    settings['workflow_rules_migrated_at'].present?
  end
end
