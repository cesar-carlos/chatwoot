class Custom::ConversationWorkflow::Scopes::CustomerNoReplyScope
  INCOMING_TYPE = Message.message_types[:incoming]
  OUTGOING_TYPE = Message.message_types[:outgoing]

  def initialize(account:, rule:)
    @account = account
    @rule = rule
  end

  def perform
    scope = @account.conversations.open.where.not(contact_id: nil)
    scope = scope.where(inbox_id: Array(@rule.inbox_ids)) if @rule.inbox_ids.present?

    multiplier = @rule.respect_business_hours? ? 3 : 1
    cutoff = Time.now.utc - (@rule.duration_minutes * multiplier).minutes
    scope.where(last_outgoing_message_older_than_sql, cutoff)
  end

  private

  def last_outgoing_message_older_than_sql
    <<~SQL.squish
      EXISTS (
        SELECT 1 FROM messages lm
        WHERE lm.conversation_id = conversations.id
          AND lm.message_type = #{OUTGOING_TYPE}
          AND lm.id = (
            SELECT m2.id FROM messages m2
            WHERE m2.conversation_id = conversations.id
              AND m2.message_type IN (#{INCOMING_TYPE}, #{OUTGOING_TYPE})
            ORDER BY m2.created_at DESC
            LIMIT 1
          )
          AND lm.created_at < ?
      )
    SQL
  end
end
