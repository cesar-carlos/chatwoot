class Custom::ConversationWorkflow::PreviewCountService
  PREVIEW_LIMIT = 10_000

  def initialize(account:, attributes:)
    @account = account
    @attributes = attributes
  end

  def perform
    rule = build_rule
    return 0 unless feature_enabled_for?(rule)

    scope = scope_for(rule)
    scope = scope.limit(PREVIEW_LIMIT + 1)
    count = 0
    scope.find_each do |conversation|
      next unless executor_for(rule).fully_eligible?(conversation)

      count += 1
      break if count > PREVIEW_LIMIT
    end
    [count, PREVIEW_LIMIT].min
  end

  private

  def executor_for(rule)
    Custom::ConversationWorkflow::RuleExecutor.new(account: @account, rule: rule)
  end

  def build_rule
    ConversationWorkflowRule.new(@attributes.merge(account: @account))
  end

  def scope_for(rule)
    executor_for(rule).matching_scope
  end

  def feature_enabled_for?(rule)
    flag = Custom::ConversationWorkflow::AccountProcessor::FEATURE_FLAG_BY_TRIGGER[rule.trigger_type]
    flag.blank? || @account.feature_enabled?(flag)
  end
end
