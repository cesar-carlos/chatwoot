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
    Wavoip::Calls::ConversationLinker.link_inbound!(inbox: inbox, event: event)
  end

  def finalize_stub(call)
    call.update!(
      status: 'completed',
      end_reason: 'handled_remotely',
      meta: stub_meta(call)
    )
    Voice::CallMessageBuilder.new(call).update_status!(
      status: call.status,
      agent: nil,
      duration_seconds: call.duration_seconds
    )
    update_conversation(call)
    broadcaster.broadcast_ended(call)
    mark_webhook_verified!
    call
  end

  def stub_meta(call)
    (call.meta || {}).merge(
      'wavoip_status' => event.external_status,
      'ended_at' => Time.zone.now.to_i
    )
  end

  def update_conversation(call)
    call.conversation.update!(
      additional_attributes: (call.conversation.additional_attributes || {}).merge(
        'call_status' => call.display_status,
        'call_direction' => call.direction_label
      )
    )
  end

  def mark_webhook_verified!
    channel = inbox.channel
    return unless channel.is_a?(Channel::Wavoip)
    return if channel.webhook_verified?

    config = (channel.provider_config || {}).dup
    config['webhook_verified_at'] = Time.current.iso8601
    channel.update!(provider_config: config)
  end
end
