class Custom::ConversationWorkflow::Scopes::InactivityScope
  def initialize(account:, rule:)
    @account = account
    @rule = rule
  end

  def perform
    scope = @account.conversations.open.where.not(contact_id: nil)
    scope = scope.where(waiting_since: nil) if @rule.ignore_waiting?
    scope = scope.where(inbox_id: Array(@rule.inbox_ids)) if @rule.inbox_ids.present?
    apply_cutoff(scope)
  end

  private

  def apply_cutoff(scope)
    multiplier = @rule.respect_business_hours? ? 3 : 1
    cutoff = Time.now.utc - (@rule.duration_minutes * multiplier).minutes
    scope.where('last_activity_at < ?', cutoff)
  end
end
