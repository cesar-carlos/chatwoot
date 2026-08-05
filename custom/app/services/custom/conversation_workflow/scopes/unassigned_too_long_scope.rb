class Custom::ConversationWorkflow::Scopes::UnassignedTooLongScope
  def initialize(account:, rule:)
    @account = account
    @rule = rule
  end

  def perform
    scope = @account.conversations.open
                    .where(assignee_id: nil)
                    .where.not(contact_id: nil)
    scope = scope.where(inbox_id: Array(@rule.inbox_ids)) if @rule.inbox_ids.present?
    apply_cutoff(scope)
  end

  private

  def apply_cutoff(scope)
    multiplier = @rule.respect_business_hours? ? 3 : 1
    cutoff = Time.now.utc - (@rule.duration_minutes * multiplier).minutes
    scope.where('conversations.created_at < ?', cutoff)
  end
end
