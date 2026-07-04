# frozen_string_literal: true

class Wavoip::Calls::HandledRemotelyStubService
  def initialize(inbox:, event:, broadcaster:, invalid_contact_phone:)
    @inbox = inbox
    @event = event
    @broadcaster = broadcaster
    @invalid_contact_phone = invalid_contact_phone
  end

  def perform
    return if event.external_call_id.blank?
    return if invalid_contact_phone.call

    finalize_stub(link_stub_call)
  rescue StandardError => e
    Rails.logger.warn(
      "[WAVOIP] HANDLED_REMOTELY stub failed inbox_id=#{inbox.id} " \
      "call_id=#{event.external_call_id}: #{e.message}"
    )
    nil
  end

  private

  attr_reader :inbox, :event, :broadcaster, :invalid_contact_phone

  def link_stub_call
    Wavoip::Calls::ConversationLinker.link!(inbox: inbox, event: event)
  end

  def finalize_stub(call)
    call.with_lock do
      call.update!(
        status: 'completed',
        end_reason: 'handled_remotely',
        meta: stub_meta(call)
      )
    end
    Wavoip::Calls::CallFinalizer.finalize_ended!(call, broadcaster: broadcaster, agent: nil)
    inbox.channel.mark_webhook_verified!
    call
  end

  def stub_meta(call)
    (call.meta || {}).merge(
      'wavoip_status' => event.external_status,
      'ended_at' => Time.zone.now.to_i
    )
  end
end
