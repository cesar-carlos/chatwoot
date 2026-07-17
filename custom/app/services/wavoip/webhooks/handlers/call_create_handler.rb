# frozen_string_literal: true

class Wavoip::Webhooks::Handlers::CallCreateHandler < Wavoip::Webhooks::Handlers::BaseHandler
  def perform
    return if event.external_call_id.blank?

    call = Wavoip::Calls::CallUpsertService.new(inbox: inbox, event: event).create!
    record_outbound_volume! if call.present? && event.direction == :outgoing
    call
  end

  private

  def record_outbound_volume!
    Wavoip::Calls::OutboundVolumeGuard.increment_and_warn_level(inbox.account_id)
  end
end
