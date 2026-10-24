# frozen_string_literal: true

# One-shot inference for conversations created before opened_by was stamped.
# Does not run on a schedule. Invoke from `opened_by:backfill` or OpenedByBackfillJob.
class Custom::Conversations::OpenedByBackfill
  def self.perform!(account_id: nil)
    scope = Conversation.where("COALESCE(additional_attributes ->> 'opened_by', '') = ''")
    scope = scope.where(account_id: account_id) if account_id.present?

    stamped = 0
    scope.find_each do |conversation|
      value = infer(conversation)
      next if value.blank?

      Custom::Conversations::OpenedByStamper.stamp!(conversation, value)
      stamped += 1
    end
    stamped
  end

  def self.infer(conversation)
    message = conversation.messages.where.not(message_type: :activity).order(:created_at, :id).first
    origin_for(message)
  end

  def self.origin_for(message)
    return if message.blank?

    attrs = message.content_attributes || {}
    return Custom::Conversations::OpenedByStamper::PHONE if phone_message?(message, attrs)
    return Custom::Conversations::OpenedByStamper::CONTACT if message.incoming?
    return Custom::Conversations::OpenedByStamper::AGENT if message.outgoing? || message.template?

    nil
  end

  def self.phone_message?(message, attrs)
    truthy?(attrs['phone_sent']) || (message.outgoing? && truthy?(attrs['external_echo']))
  end

  def self.truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end
  private_class_method :origin_for, :phone_message?, :truthy?
end
