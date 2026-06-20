module Custom::Account
  extend ActiveSupport::Concern

  prepended do
    has_many :conversation_workflow_rules, dependent: :destroy_async
    has_many :wavoip_channels, class_name: 'Channel::Wavoip', dependent: :destroy_async, foreign_key: 'account_id'
  end

  def workflow_rules_migrated?
    settings['workflow_rules_migrated_at'].present?
  end
end
