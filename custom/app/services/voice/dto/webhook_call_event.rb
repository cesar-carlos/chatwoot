# frozen_string_literal: true

module Voice::Dto
  WebhookCallEvent = Data.define(
    :provider,
    :external_call_id,
    :action,
    :external_status,
    :direction,
    :from_phone,
    :to_phone,
    :peer_name,
    :duration_seconds,
    :session_id,
    :call_type,
    :record_url,
    :raw_type
  ) do
    def create? = action == :create
    def update? = action == :update
  end
end
