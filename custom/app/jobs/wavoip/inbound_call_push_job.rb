# frozen_string_literal: true

class Wavoip::InboundCallPushJob < ApplicationJob
  queue_as :default

  def perform(call_id)
    call = Call.find_by(id: call_id)
    return if call.blank?

    Wavoip::Calls::InboundPushService.new(call: call, inbox: call.inbox).perform
  end
end
