# frozen_string_literal: true

class Wavoip::Calls::CallLookup
  def self.find(inbox:, provider_call_id:)
    Call.find_by(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      provider: :wavoip,
      provider_call_id: provider_call_id.to_s
    )
  end
end
