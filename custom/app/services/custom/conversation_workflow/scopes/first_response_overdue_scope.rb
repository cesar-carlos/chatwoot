class Custom::ConversationWorkflow::Scopes::FirstResponseOverdueScope
  def initialize(account:, rule:)
    @account = account
    @rule = rule
  end

  def perform
    statuses = @rule.status_names.map { |name| Conversation.statuses[name] }
    scope = @account.conversations.where(status: statuses)
                    .where(first_reply_created_at: nil)
                    .where.not(waiting_since: nil)
                    .where.not(contact_id: nil)
    scope = scope.where(inbox_id: Array(@rule.inbox_ids)) if @rule.inbox_ids.present?
    apply_cutoff(scope)
  end

  private

  def apply_cutoff(scope)
    return scope if @rule.respect_business_hours?

    cutoff = Time.now.utc - @rule.duration_minutes.minutes
    scope.where('waiting_since < ?', cutoff)
  end
end
