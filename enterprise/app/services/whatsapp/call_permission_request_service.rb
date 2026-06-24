# frozen_string_literal: true

# Handles the opt-in flow when Meta returns error 138006 (contact has not
# authorized outbound WhatsApp calls). Sends the interactive
# `call_permission_request` template (throttled per conversation), records the
# outbound WAMID for reply matching, and emits an activity message.
#
# Returns one of: :permission_requested | :permission_pending | :failed
class Whatsapp::CallPermissionRequestService
  THROTTLE = 5.minutes

  pattr_initialize [:conversation!, :agent!]

  def perform
    status = nil

    conversation.with_lock do
      if throttled?
        status = :permission_pending
        next
      end

      sent = send_request_safely
      if sent
        record_wamid(sent)
        emit_activity
        status = :permission_requested
      else
        status = :failed
      end
    end

    status
  end

  private

  attr_reader :conversation, :agent

  def channel
    @channel ||= conversation.inbox.channel
  end

  def provider_service
    @provider_service ||= channel.provider_service
  end

  def throttled?
    last_requested = conversation.additional_attributes&.dig('call_permission_requested_at')
    last_requested.present? && Time.zone.parse(last_requested) > THROTTLE.ago
  end

  # Treat transport errors as falsy so the caller can render a 422 rather than 500.
  def send_request_safely
    provider_service.send_call_permission_request(
      conversation.contact.phone_number.delete('+'),
      *custom_body_args
    )
  rescue StandardError => e
    Rails.logger.warn "[WHATSAPP CALL] permission_request failed: #{e.class} #{e.message}"
    nil
  end

  # Pass the inbox-level override only when present so the provider falls back
  # to the i18n default for inboxes that haven't customised the prompt.
  def custom_body_args
    custom_body = channel.provider_config&.dig('call_permission_request_body').presence
    custom_body ? [custom_body] : []
  end

  def record_wamid(sent)
    attrs = (conversation.additional_attributes || {}).merge(
      'call_permission_requested_at' => Time.current.iso8601,
      'call_permission_request_message_id' => sent.dig('messages', 0, 'id')
    )
    conversation.update!(additional_attributes: attrs)
  end

  def emit_activity
    content = I18n.t(
      'conversations.activity.whatsapp_call.permission_requested',
      contact_name: conversation.contact.name
    )
    ::Conversations::ActivityMessageJob.perform_later(
      conversation,
      { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity, content: content }
    )
  end
end
