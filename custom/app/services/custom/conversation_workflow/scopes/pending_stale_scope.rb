class Custom::ConversationWorkflow::Scopes::PendingStaleScope
  def initialize(account:, rule:)
    @account = account
    @rule = rule
  end

  def perform
    scope = @account.conversations.pending.where.not(contact_id: nil)
    scope = scope.where(inbox_id: Array(@rule.inbox_ids)) if @rule.inbox_ids.present?
    apply_cutoff(scope)
  end

  private

  def apply_cutoff(scope)
    return scope if @rule.respect_business_hours?

    cutoff = Time.now.utc - @rule.duration_minutes.minutes
    scope.where('last_activity_at < ?', cutoff)
  end
end
