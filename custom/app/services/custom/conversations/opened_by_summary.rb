# frozen_string_literal: true

# Live counts of the current episode origin. Blank stamps stay in :unset.
class Custom::Conversations::OpenedBySummary
  def self.counts(scope)
    grouped = scope.group(Arel.sql("COALESCE(additional_attributes ->> 'opened_by', '')")).count
    {
      contact: grouped[Custom::Conversations::OpenedByStamper::CONTACT] || 0,
      agent: grouped[Custom::Conversations::OpenedByStamper::AGENT] || 0,
      phone: grouped[Custom::Conversations::OpenedByStamper::PHONE] || 0,
      unset: grouped[''] || 0
    }
  end
end
